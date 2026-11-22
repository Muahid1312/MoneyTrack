import '../../../core/constants/currency.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/wallet.dart';

DateTime shiftLedgerMonth(DateTime selected, int delta) {
  final first = DateTime(selected.year, selected.month + delta);
  return DateTime(
    first.year,
    first.month,
    selected.day.clamp(1, Dates.daysInMonth(first)),
  );
}

class LedgerRecord {
  LedgerRecord.transaction(TransactionModel entry)
    : transaction = entry,
      transfer = null,
      date = entry.occurredAt;
  LedgerRecord.transfer(WalletTransfer entry)
    : transaction = null,
      transfer = entry,
      date = entry.occurredAt;
  final TransactionModel? transaction;
  final WalletTransfer? transfer;
  final DateTime date;
}

class LedgerDay {
  int income = 0, expense = 0;
  final records = <LedgerRecord>[];
}

class LedgerMonth {
  LedgerMonth(
    DateTime selected,
    AppCurrency currency,
    Iterable<TransactionModel> transactions,
    Iterable<WalletTransfer> transfers,
  ) {
    final span = DateSpan.month(selected);
    LedgerDay day(DateTime date) => days.putIfAbsent(date.day, LedgerDay.new);
    for (final t in transactions) {
      if (t.currency != currency || !span.contains(t.occurredAt)) continue;
      final d = day(t.occurredAt);
      d.records.add(LedgerRecord.transaction(t));
      if (t.type.isIncome) {
        d.income += t.amountMinor;
        income += t.amountMinor;
      } else {
        d.expense += t.amountMinor;
        expense += t.amountMinor;
      }
    }
    for (final t in transfers) {
      if (span.contains(t.occurredAt) &&
          (t.sourceCurrency == currency || t.destinationCurrency == currency)) {
        day(t.occurredAt).records.add(LedgerRecord.transfer(t));
      }
    }
    for (final d in days.values) {
      d.records.sort((a, b) {
        final order = b.date.compareTo(a.date);
        if (order != 0) return order;
        if ((a.transaction == null) != (b.transaction == null)) {
          return a.transaction == null ? 1 : -1;
        }
        return (b.transaction?.id ?? b.transfer?.id ?? 0).compareTo(
          a.transaction?.id ?? a.transfer?.id ?? 0,
        );
      });
    }
  }
  final days = <int, LedgerDay>{};
  int income = 0, expense = 0;
}
