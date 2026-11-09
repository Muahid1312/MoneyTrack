import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/categories.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';

@immutable
class Totals {
  const Totals({this.income = 0, this.expense = 0, this.count = 0});
  final int income;
  final int expense;
  final int count;
  int get net => income - expense;
}

@immutable
class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.amountMinor,
    required this.fraction,
    required this.count,
  });
  final TransactionCategory category;
  final int amountMinor;

  /// Share of the total (0..1). Display only.
  final double fraction;
  final int count;
}

@immutable
class PeriodBucket {
  const PeriodBucket({
    required this.span,
    required this.label,
    required this.longLabel,
    this.income = 0,
    this.expense = 0,
  });
  final DateSpan span;
  final String label;
  final String longLabel;
  final int income;
  final int expense;
}

enum BucketSize { day, week, month }

/// Pure, side-effect free aggregation over transactions. All sums are
/// integer minor units.
abstract final class FinanceCalculator {
  static Iterable<TransactionModel> inSpan(
          Iterable<TransactionModel> txs, DateSpan span) =>
      txs.where((t) => span.contains(t.occurredAt));

  static void _requireSingleCurrency(Iterable<TransactionModel> txs) {
    if (txs.map((t) => t.currency).toSet().length > 1) {
      throw ArgumentError('Select one currency before calculating totals');
    }
  }

  static Totals totals(Iterable<TransactionModel> txs, {DateSpan? span}) {
    _requireSingleCurrency(txs);
    var income = 0, expense = 0, count = 0;
    for (final t in txs) {
      if (span != null && !span.contains(t.occurredAt)) continue;
      count++;
      if (t.type.isIncome) {
        income += t.amountMinor;
      } else {
        expense += t.amountMinor;
      }
    }
    return Totals(income: income, expense: expense, count: count);
  }

  static int balance(Iterable<TransactionModel> txs) {
    _requireSingleCurrency(txs);
    return txs.fold(0, (sum, t) => sum + t.signedMinor);
  }

  /// Expense totals per day for [days] days starting at [firstDay].
  static List<int> dailyExpenses(
      Iterable<TransactionModel> txs, DateTime firstDay, int days) {
    _requireSingleCurrency(txs);
    final start = Dates.dateOnly(firstDay);
    final out = List<int>.filled(days, 0);
    for (final t in txs) {
      if (!t.type.isExpense) continue;
      final i = Dates.daysBetween(start, t.occurredAt);
      if (i >= 0 && i < days) out[i] += t.amountMinor;
    }
    return out;
  }

  static List<CategoryShare> expenseByCategory(
      Iterable<TransactionModel> txs, DateSpan span) {
    _requireSingleCurrency(txs);
    final sums = <String, int>{};
    final counts = <String, int>{};
    var total = 0;
    for (final t in txs) {
      if (!t.type.isExpense || !span.contains(t.occurredAt)) continue;
      sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amountMinor;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      total += t.amountMinor;
    }
    final list = sums.entries
        .map((e) => CategoryShare(
              category: Categories.byId(e.key),
              amountMinor: e.value,
              fraction: total == 0 ? 0 : e.value / total,
              count: counts[e.key]!,
            ))
        .toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return list;
  }

  /// Picks a readable bucket size for the span.
  static BucketSize bucketFor(DateSpan span, {bool forTrend = false}) {
    final d = span.days;
    if (forTrend) {
      if (d <= 45) return BucketSize.day;
      if (d <= 190) return BucketSize.week;
      return BucketSize.month;
    }
    return d <= 45 ? BucketSize.week : BucketSize.month;
  }

  static List<PeriodBucket> buckets(
      Iterable<TransactionModel> txs, DateSpan span, BucketSize size) {
    _requireSingleCurrency(txs);
    final spans = <DateSpan>[];
    var cursor = span.start;
    while (cursor.isBefore(span.end)) {
      DateTime next;
      switch (size) {
        case BucketSize.day:
          next = Dates.addDays(cursor, 1);
        case BucketSize.week:
          next = Dates.addDays(cursor, 7);
        case BucketSize.month:
          next = DateTime(cursor.year, cursor.month + 1);
      }
      if (next.isAfter(span.end)) next = span.end;
      spans.add(DateSpan(cursor, next));
      cursor = next;
    }

    final income = List<int>.filled(spans.length, 0);
    final expense = List<int>.filled(spans.length, 0);
    for (final t in txs) {
      if (!span.contains(t.occurredAt)) continue;
      final i = _indexOf(spans, t.occurredAt, size, span.start);
      if (i < 0) continue;
      if (t.type.isIncome) {
        income[i] += t.amountMinor;
      } else {
        expense[i] += t.amountMinor;
      }
    }

    return [
      for (var i = 0; i < spans.length; i++)
        PeriodBucket(
          span: spans[i],
          label: _label(spans[i], size),
          longLabel: _longLabel(spans[i], size),
          income: income[i],
          expense: expense[i],
        ),
    ];
  }

  static int _indexOf(
      List<DateSpan> spans, DateTime t, BucketSize size, DateTime origin) {
    switch (size) {
      case BucketSize.day:
        return Dates.daysBetween(origin, t).clamp(-1, spans.length - 1);
      case BucketSize.week:
        final i = Dates.daysBetween(origin, t) ~/ 7;
        return i < spans.length ? i : -1;
      case BucketSize.month:
        for (var i = 0; i < spans.length; i++) {
          if (spans[i].contains(t)) return i;
        }
        return -1;
    }
  }

  static String _label(DateSpan s, BucketSize size) => switch (size) {
        BucketSize.day => DateFormat('d').format(s.start),
        BucketSize.week => DateFormat('MMM d').format(s.start),
        BucketSize.month => DateFormat('MMM').format(s.start),
      };

  static String _longLabel(DateSpan s, BucketSize size) => switch (size) {
        BucketSize.day => DateFormat('EEE, MMM d').format(s.start),
        BucketSize.week => Dates.spanLabel(s),
        BucketSize.month => DateFormat('MMMM y').format(s.start),
      };

  /// Average expense per elapsed day in [span] (days after [now] excluded).
  static int averageDailyExpense(
      Iterable<TransactionModel> txs, DateSpan span, DateTime now) {
    final tomorrow = Dates.addDays(Dates.dateOnly(now), 1);
    final effectiveEnd = span.end.isAfter(tomorrow) ? tomorrow : span.end;
    final days = Dates.daysBetween(span.start, effectiveEnd);
    if (days <= 0) return 0;
    final spent = totals(txs, span: DateSpan(span.start, effectiveEnd)).expense;
    return (spent * 2 + days) ~/ (days * 2);
  }

  /// Percentage change from [previous] to [current]; null when undefined.
  static double? percentChange(int previous, int current) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}
