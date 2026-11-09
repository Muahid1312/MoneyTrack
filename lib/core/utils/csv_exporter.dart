import 'package:intl/intl.dart';

import '../../data/models/transaction.dart';
import 'money.dart';

/// RFC 4180 CSV for transactions. Amounts are exact decimals derived from
/// integer minor units; expenses are negative in the signed column.
abstract final class CsvExporter {
  static const header = [
    'id',
    'date',
    'time',
    'type',
    'category',
    'description',
    'amount',
    'signed_amount',
    'currency',
    'wallet_id',
    'project_id', 'project_category_id', 'project_amount', 'project_currency',
    'project_rate', 'client_receipt', 'payment_reference',
  ];

  static String build(List<TransactionModel> txs, String currencyCode) {
    final date = DateFormat('yyyy-MM-dd');
    final time = DateFormat('HH:mm');
    final rows = <List<String>>[
      header,
      for (final t in txs)
        [
          '${t.id ?? ''}',
          date.format(t.occurredAt),
          time.format(t.occurredAt),
          t.type.storageKey,
          t.category.name,
          t.note,
          Money.plain(t.amountMinor, t.currency),
          Money.plain(t.signedMinor, t.currency),
          t.currency.code,
          '${t.walletId}',
          '${t.projectId ?? ''}', '${t.projectCategoryId ?? ''}',
          t.projectAmountMinor == null || t.projectCurrency == null ? '' : Money.plain(t.projectAmountMinor!, t.projectCurrency!),
          t.projectCurrency?.code ?? '', t.projectRate ?? '',
          t.clientReceipt ? 'yes' : 'no', t.paymentReference ?? '',
        ],
    ];
    return '${rows.map((r) => r.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _escape(String v) {
    // Neutralise spreadsheet formula injection.
    var s = v;
    if (RegExp(r'^[=+\-@\t\r]').hasMatch(s.trimLeft()) && !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      s = "'$s";
    }
    if (s.contains(RegExp(r'[",\r\n]'))) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
