import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show ImmutableBuffer, ImageDescriptor;

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/currency.dart';
import '../../features/managed_funds/domain/managed_fund.dart';
import '../database/app_database.dart';
import '../storage/access_guard.dart';

String managedRequestKey() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

final _random = Random.secure();

class ManagedFundDetail {
  const ManagedFundDetail(this.ledger, this.items);
  final ManagedLedger ledger;
  final Map<int, List<PurchaseLine>> items;
}

class ManagedReceipt {
  const ManagedReceipt(this.id, this.name);
  final int id;
  final String name;
}

class ManagedFundRepository {
  ManagedFundRepository(this.database);
  final AppDatabase database;
  static const maxReceiptBytes = 2 * 1024 * 1024;
  static const maxReceiptsPerPurchase = 5;

  Future<List<ManagedFund>> list() async => [
    for (final r in await database.db.query(
      'managed_funds',
      orderBy: 'id DESC',
    ))
      ManagedFund.fromRow(r),
  ];

  Future<ManagedFundDetail> get(int fundId) =>
      database.db.transaction((tx) async {
        final ledger = await _read(tx, fundId);
        final items = await tx.rawQuery(
          '''
      SELECT i.* FROM managed_events e JOIN managed_purchase_items i ON i.event_id=e.id
      WHERE e.fund_id=? ORDER BY e.id,i.id
    ''',
          [fundId],
        );
        final purchases = <int, List<PurchaseLine>>{};
        for (final item in items) {
          (purchases[item['event_id'] as int] ??= []).add(
            PurchaseLine.fromRow(item),
          );
        }
        return ManagedFundDetail(ledger, purchases);
      });

  static Future<ManagedLedger> _read(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'managed_funds',
      where: 'id=?',
      whereArgs: [id],
    );
    requireManaged(rows.isNotEmpty, 'This fund is unavailable.');
    final ledger = ManagedLedger(ManagedFund.fromRow(rows.single));
    for (final row in await db.query(
      'managed_events',
      where: 'fund_id=?',
      whereArgs: [id],
      orderBy: 'id',
    )) {
      ledger.apply(FundEvent.fromRow(row));
    }
    return ledger;
  }

  Future<int> create({
    required String key,
    required String name,
    required String provider,
    required AppCurrency currency,
    required int initialMinor,
    required DateTime date,
    required String method,
    String description = '',
    String purpose = '',
    DateTime? expected,
    String notes = '',
    String fundingNote = '',
    FundIcon icon = FundIcon.fund,
  }) {
    final fund = {
      'name': _text(name, 'fund name', 120, required: true),
      'provider': _text(provider, 'provider', 120, required: true),
      'currency': currency.code,
      'opened_at': date.millisecondsSinceEpoch,
      'description': _text(description, 'description', 1000),
      'purpose': _text(purpose, 'purpose', 120),
      'expected_at': expected?.millisecondsSinceEpoch,
      'notes': _text(notes, 'notes', 1000),
      'icon': icon.name,
    };
    requireManaged(
      expected == null ||
          !DateTime(
            expected.year,
            expected.month,
            expected.day,
          ).isBefore(DateTime(date.year, date.month, date.day)),
      'The expected completion date must be on or after the opening date.',
    );
    final posting = _posting(
      FundEventKind.funding,
      cash: initialMinor,
      date: date,
      party: provider,
      method: method,
      note: fundingNote,
    );
    return _perform(key, ['create', fund, posting], null, (tx, _) async {
      final id = await tx.insert('managed_funds', fund);
      return (id, await _insert(tx, await _read(tx, id), posting));
    }).then((r) => r.$1);
  }

  Future<int> funding(
    int fundId, {
    required String key,
    required int amount,
    required String provider,
    required DateTime date,
    required String method,
    String note = '',
    int? correct,
  }) {
    final posting = _posting(
      FundEventKind.funding,
      cash: amount,
      target: correct,
      date: date,
      party: provider,
      method: method,
      note: note,
    );
    return _mutate(fundId, key, ['funding', posting, correct], (
      tx,
      ledger,
    ) async {
      // Post the replacement first so correcting a spent deposit is possible
      // whenever the corrected balance remains nonnegative.
      final old = correct == null
          ? null
          : _event(ledger, correct, FundEventKind.funding);
      requireManaged(
        old == null || !ledger.reversed(old.id),
        'This funding has already been reversed.',
      );
      final id = await _insert(tx, ledger, posting);
      if (old != null) {
        await _insert(
          tx,
          ledger,
          _reversal(
            old,
            FundEventKind.fundingReversal,
            date,
            note.isEmpty ? 'Funding correction' : note,
          ),
        );
      }
      return id;
    });
  }

  Future<int> purchase(
    int fundId, {
    required String key,
    required List<PurchaseLine> items,
    required int cash,
    required DateTime date,
    required String method,
    String shop = '',
    String note = '',
    int? correct,
  }) {
    requireManaged(
      items.isNotEmpty && items.length <= 100,
      'Enter 1 to 100 purchase items.',
    );
    final entries = items.map((line) => line.toRow()).toList();
    final total = items.fold(0, (sum, line) => sum + line.total);
    final posting = _posting(
      FundEventKind.purchase,
      cash: cash,
      personal: total - cash,
      target: correct,
      date: date,
      party: shop.trim().isEmpty ? 'Purchase' : shop,
      method: method,
      note: note,
    );
    return _mutate(fundId, key, ['purchase', posting, entries, correct], (
      tx,
      ledger,
    ) async {
      if (correct != null) {
        final old = _event(ledger, correct, FundEventKind.purchase);
        await _insert(
          tx,
          ledger,
          _reversal(
            old,
            FundEventKind.purchaseReversal,
            date,
            'Purchase correction',
          ),
        );
      }
      final id = await _insert(tx, ledger, posting);
      for (final row in entries) {
        await tx.insert('managed_purchase_items', {...row, 'event_id': id});
      }
      if (correct != null) {
        await tx.rawInsert(
          '''
          INSERT INTO managed_receipts(event_id,name,data,sha256)
          SELECT ?,name,data,sha256 FROM managed_receipts WHERE event_id=?
        ''',
          [id, correct],
        );
      }
      return id;
    });
  }

  Future<int> refund(
    int fundId, {
    required String key,
    required int purchase,
    required int cash,
    required int personal,
    required DateTime date,
    required String merchant,
    required String method,
    String note = '',
  }) {
    final posting = _posting(
      FundEventKind.refund,
      target: purchase,
      cash: cash,
      personal: personal,
      date: date,
      party: merchant,
      method: method,
      note: note,
    );
    return _mutate(
      fundId,
      key,
      posting,
      (tx, ledger) => _insert(tx, ledger, posting),
    );
  }

  Future<int> reimburse(
    int fundId, {
    required String key,
    required int purchase,
    required int amount,
    required bool fromFund,
    required DateTime date,
    required String provider,
    required String method,
    String note = '',
  }) {
    final posting = _posting(
      fromFund ? FundEventKind.reimburseCash : FundEventKind.reimburseDirect,
      target: purchase,
      cash: fromFund ? amount : 0,
      personal: fromFund ? 0 : amount,
      date: date,
      party: provider,
      method: method,
      note: note,
    );
    return _mutate(
      fundId,
      key,
      posting,
      (tx, ledger) => _insert(tx, ledger, posting),
    );
  }

  Future<int> reverse(
    int fundId, {
    required String key,
    required int target,
    required DateTime date,
    required String reason,
  }) {
    final note = _text(reason, 'reason', 1000, required: true);
    return _mutate(
      fundId,
      key,
      ['reverse', target, date.millisecondsSinceEpoch, note],
      (tx, ledger) {
        final old = _event(ledger, target);
        final kind = switch (old.kind) {
          FundEventKind.funding => FundEventKind.fundingReversal,
          FundEventKind.purchase => FundEventKind.purchaseReversal,
          FundEventKind.refund => FundEventKind.refundReversal,
          FundEventKind.reimburseCash ||
          FundEventKind.reimburseDirect => FundEventKind.reimbursementReversal,
          _ => throw const FundRule('This record does not support a reversal.'),
        };
        return _insert(tx, ledger, _reversal(old, kind, date, note));
      },
    );
  }

  static FundEvent _event(ManagedLedger ledger, int id, [FundEventKind? kind]) {
    final event = ledger.event(id);
    requireManaged(
      event != null && (kind == null || kind == event.kind),
      'This posting is unavailable in the selected fund.',
    );
    return event!;
  }

  static FundRow _reversal(
    FundEvent old,
    FundEventKind kind,
    DateTime date,
    String note,
  ) => _posting(
    kind,
    cash: old.cash,
    personal: old.personal,
    target: old.id,
    date: date,
    party: old.party,
    method: old.method,
    note: note,
  );

  static FundRow _posting(
    FundEventKind kind, {
    int? target,
    int cash = 0,
    int personal = 0,
    required DateTime date,
    required String party,
    required String method,
    required String note,
  }) {
    requireManaged(
      cash >= 0 &&
          personal >= 0 &&
          cash <= AppInfo.maxAmountMinor &&
          personal <= AppInfo.maxAmountMinor &&
          cash + personal > 0 &&
          cash + personal <= AppInfo.maxAmountMinor,
      'Enter an amount within the supported range and check the payment split.',
    );
    return {
      'kind': kind.name,
      'target_id': target,
      'cash_minor': cash,
      'personal_minor': personal,
      'occurred_at': date.millisecondsSinceEpoch,
      'party': _text(party, 'provider or shop', 120, required: true),
      'method': _text(method, 'payment method', 80, required: true),
      'note': _text(note, 'note', 1000),
    };
  }

  static String _text(
    String text,
    String label,
    int max, {
    bool required = false,
  }) {
    final trimmed = text.trim();
    requireManaged(
      trimmed.length <= max && (!required || trimmed.isNotEmpty),
      required
          ? 'Enter a $label of 1 to $max characters.'
          : 'The $label is too long.',
    );
    return trimmed;
  }

  static Future<int> _insert(
    Transaction tx,
    ManagedLedger ledger,
    FundRow posting,
  ) async {
    final target = posting['target_id'] as int?;
    if (target != null) _event(ledger, target);
    final id = await tx.insert('managed_events', {
      ...posting,
      'fund_id': ledger.fund.id,
    });
    ledger.apply(FundEvent.fromRow({...posting, 'id': id}));
    return id;
  }

  Future<int> _mutate(
    int fund,
    String key,
    Object payload,
    Future<int> Function(Transaction, ManagedLedger) apply,
  ) => _perform(
    key,
    payload,
    fund,
    (tx, ledger) async => (fund, await apply(tx, ledger!)),
  ).then((r) => r.$2);

  Future<(int, int)> _perform(
    String key,
    Object payload,
    int? fund,
    Future<(int, int)> Function(Transaction, ManagedLedger?) apply,
  ) async {
    AccessGuard.writable();
    final token = _text(key, 'submission identifier', 128, required: true);
    final digest = await _digest(utf8.encode(jsonEncode([fund, payload])));
    return database.db.transaction((tx) async {
      AccessGuard.writable();
      final rows = await tx.query(
        'managed_requests',
        where: 'request_key=?',
        whereArgs: [token],
      );
      if (rows.isNotEmpty) {
        final row = rows.single;
        requireManaged(
          row['fingerprint'] == digest,
          'This submission key is already in use.',
        );
        return (row['fund_id'] as int, row['event_id'] as int);
      }
      final ledger = fund == null ? null : await _openLedger(tx, fund);
      final result = await apply(tx, ledger);
      await tx.insert('managed_requests', {
        'request_key': token,
        'fingerprint': digest,
        'fund_id': result.$1,
        'event_id': result.$2,
      });
      return result;
    });
  }

  static Future<ManagedLedger> _openLedger(DatabaseExecutor tx, int id) async {
    final ledger = await _read(tx, id);
    requireManaged(
      ledger.fund.status == FundStatus.active,
      'Only active funds accept new records.',
    );
    return ledger;
  }

  static Future<String> _digest(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  static bool _isPhoto(List<int> b) =>
      b.length > 8 &&
      ((b[0] == 255 && b[1] == 216 && b[2] == 255) ||
          (b.take(8).join(',') == '137,80,78,71,13,10,26,10'));

  static Future<void> _validatePhoto(Uint8List bytes) async {
    requireManaged(
      bytes.length <= maxReceiptBytes && _isPhoto(bytes),
      'Choose a JPEG or PNG photo up to 2 MiB.',
    );
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    ImageDescriptor? image;
    try {
      image = await ImageDescriptor.encoded(buffer);
      requireManaged(
        image.width * image.height <= 16000000,
        'Choose a photo with at most 16 megapixels.',
      );
    } on Exception {
      throw const FundRule('This receipt photo could not be decoded.');
    } finally {
      image?.dispose();
      buffer.dispose();
    }
  }

  Future<List<ManagedReceipt>> receipts(int fund, int purchase) async {
    final rows = await database.db.rawQuery(
      '''
      SELECT r.id,r.name FROM managed_receipts r JOIN managed_events e ON e.id=r.event_id
      WHERE e.fund_id=? AND e.id=? ORDER BY r.id
    ''',
      [fund, purchase],
    );
    return [
      for (final r in rows) ManagedReceipt(r['id'] as int, r['name'] as String),
    ];
  }

  Future<Uint8List> receipt(int fund, int purchase, int id) async {
    final rows = await database.db.rawQuery(
      '''
      SELECT r.* FROM managed_receipts r JOIN managed_events e ON e.id=r.event_id
      WHERE e.fund_id=? AND e.id=? AND r.id=?
    ''',
      [fund, purchase, id],
    );
    requireManaged(rows.isNotEmpty, 'This receipt is unavailable.');
    return _receiptBytes(rows.single);
  }

  static Future<Uint8List> _receiptBytes(FundRow row) async {
    final bytes = base64Decode(row['data'] as String);
    await _validatePhoto(bytes);
    requireManaged(
      await _digest(bytes) == row['sha256'],
      'Receipt integrity check failed.',
    );
    return bytes;
  }

  Future<void> saveReceipt(
    int fund,
    int purchase, {
    required String name,
    required Uint8List bytes,
    int? replace,
  }) async {
    AccessGuard.writable();
    final safeName = _text(name, 'receipt name', 120, required: true);
    await _validatePhoto(bytes);
    final encoded = base64Encode(bytes);
    final digest = await _digest(bytes);
    await database.db.transaction((tx) async {
      AccessGuard.writable();
      final ledger = await _openLedger(tx, fund);
      _event(ledger, purchase, FundEventKind.purchase);
      requireManaged(
        !ledger.reversed(purchase),
        'Receipts on reversed purchases are read-only.',
      );
      final rows = await tx.query(
        'managed_receipts',
        columns: ['id', 'sha256'],
        where: 'event_id=?',
        whereArgs: [purchase],
      );
      if (replace != null) {
        requireManaged(
          rows.any((r) => r['id'] == replace),
          'This receipt is unavailable.',
        );
      }
      if (rows.any(
        (r) => r['sha256'] == digest && (replace == null || r['id'] == replace),
      )) {
        return;
      }
      requireManaged(
        !rows.any((r) => r['sha256'] == digest),
        'This photo is already attached.',
      );
      final values = {'name': safeName, 'data': encoded, 'sha256': digest};
      if (replace != null) {
        await tx.update(
          'managed_receipts',
          values,
          where: 'id=?',
          whereArgs: [replace],
        );
      } else {
        requireManaged(
          rows.length < maxReceiptsPerPurchase,
          'Attach up to five receipts per purchase.',
        );
        await tx.insert('managed_receipts', {...values, 'event_id': purchase});
      }
    });
  }

  Future<void> removeReceipt(int fund, int purchase, int id) async {
    AccessGuard.writable();
    await database.db.transaction((tx) async {
      AccessGuard.writable();
      final ledger = await _openLedger(tx, fund);
      _event(ledger, purchase, FundEventKind.purchase);
      requireManaged(
        !ledger.reversed(purchase),
        'Receipts on reversed purchases are read-only.',
      );
      await tx.delete(
        'managed_receipts',
        where: 'event_id=? AND id=?',
        whereArgs: [purchase, id],
      );
    });
  }

  static Future<void> validateAll(DatabaseExecutor db) async {
    for (final row in await db.query('managed_funds', columns: ['id'])) {
      final ledger = await _read(db, row['id'] as int);
      requireManaged(
        ledger.events.firstOrNull?.kind == FundEventKind.funding,
        'A managed fund needs initial funding.',
      );
      requireManaged(
        ledger.events.every(
          (event) =>
              event.kind != FundEventKind.funding ||
              event.target == null ||
              ledger.reversed(event.target!),
        ),
        'A funding replacement needs a matching reversal.',
      );
    }
    final rows = await db.rawQuery('''
      SELECT e.id FROM managed_events e LEFT JOIN managed_purchase_items i ON i.event_id=e.id
      GROUP BY e.id HAVING
        (e.kind='purchase' AND (COUNT(i.id) NOT BETWEEN 1 AND 100
         OR COALESCE(SUM(i.total_minor),0)!=e.cash_minor+e.personal_minor))
        OR (e.kind<>'purchase' AND COUNT(i.id)>0)
    ''');
    requireManaged(
      rows.isEmpty,
      'The purchase totals in the snapshot do not match the item lines.',
    );
    for (final row in await db.query('managed_purchase_items')) {
      PurchaseLine.fromRow(row);
    }
    final receiptTargets = await db.rawQuery('''
      SELECT e.id FROM managed_receipts r JOIN managed_events e ON e.id=r.event_id
      GROUP BY e.id HAVING e.kind<>'purchase' OR COUNT(r.id)>5
    ''');
    requireManaged(
      receiptTargets.isEmpty,
      'The snapshot has an invalid receipt reference.',
    );
    for (final row in await db.query('managed_receipts')) {
      await _receiptBytes(row);
    }
  }
}
