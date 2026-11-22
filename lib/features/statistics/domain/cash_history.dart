import '../../../core/constants/currency.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/wallet_repository.dart';

/// Reconstructs cash from current opening balances and dated cash movements.
/// The ledger has no historical versions of a wallet's opening balance.
List<({DateTime day, int minor})> cashHistory(
  WalletSnapshot snapshot,
  Iterable<TransactionModel> transactions,
  AppCurrency currency,
  DateSpan span,
  DateTime today,
) {
  final end = span.lastDay.isBefore(today)
      ? span.lastDay
      : Dates.dateOnly(today);
  if (end.isBefore(span.start)) return [];
  var cash = snapshot.wallets
      .where((w) => w.currency == currency)
      .fold<int>(0, (n, w) => n + w.openingMinor);
  final changes = <DateTime, int>{};
  void add(DateTime time, int value) {
    final day = Dates.dateOnly(time);
    if (day.isBefore(span.start)) {
      cash += value;
    } else if (!day.isAfter(end)) {
      changes.update(day, (n) => n + value, ifAbsent: () => value);
    }
  }

  for (final t in transactions) {
    if (t.currency == currency) add(t.occurredAt, t.signedMinor);
  }
  for (final t in snapshot.transfers) {
    if (t.destinationCurrency == currency)
      add(t.occurredAt, t.destinationMinor);
    if (t.sourceCurrency == currency) add(t.occurredAt, -t.sourceMinor);
  }
  for (final d in snapshot.debtPostings) {
    if (!d.voided && d.currency == currency) add(d.occurredAt, d.signedMinor);
  }
  final days = Dates.daysBetween(span.start, end);
  final step = (days + 4) ~/ 5;
  final sorted = changes.keys.toList()..sort();
  var i = 0;
  final points = <({DateTime day, int minor})>[];
  for (var offset = 0; ; offset = (offset + step).clamp(0, days)) {
    final day = Dates.addDays(span.start, offset);
    while (i < sorted.length && !sorted[i].isAfter(day)) {
      cash += changes[sorted[i++]]!;
    }
    points.add((day: day, minor: cash));
    if (offset == days) break;
  }
  return points;
}
