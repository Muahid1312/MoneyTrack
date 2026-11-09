import '../../../data/storage/access_guard.dart';
import '../../security/application/security_service.dart';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/csv_exporter.dart';
import '../../../data/models/transaction.dart';

/// Writes a CSV file locally and hands it to the system share sheet so the
/// user can save it to Files/Drive or send it. No network involved.
abstract final class DataExportService {
  static Future<File> writeCsv(List<TransactionModel> txs, AppCurrency currency) async {
    AccessGuard.writable();
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final token=SecureCrypto.random(12).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    final name = 'moneytrack-report-$token.csv';
    final file = File(p.join(dir.path, name));
    // UTF-8 BOM so spreadsheet apps detect encoding for non-ASCII notes.
    await file.writeAsString('\uFEFF${CsvExporter.build(txs, currency.code)}', flush: true);
    return file;
  }

  static Future<ShareResultStatus> share(
      File file, int count, {Rect? origin}) async {
    AccessGuard.writable();
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MoneyTrack export',
      text: 'MoneyTrack export · $count transactions',
      sharePositionOrigin: origin,
    ));
    return result.status;
  }
}
