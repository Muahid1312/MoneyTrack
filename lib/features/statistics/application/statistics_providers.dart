import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/repositories/providers.dart';
import '../../wallets/application/wallet_providers.dart';
import '../domain/finance_calculator.dart';

enum RangePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('3 months'),
  last6Months('6 months'),
  thisYear('This year'),
  custom('Custom');

  const RangePreset(this.label);
  final String label;

  DateSpan resolve(DateTime now) {
    final m = DateTime(now.year, now.month);
    return switch (this) {
      RangePreset.thisMonth => DateSpan.month(now),
      RangePreset.lastMonth => DateSpan(DateTime(m.year, m.month - 1), m),
      RangePreset.last3Months =>
        DateSpan(DateTime(m.year, m.month - 2), DateTime(m.year, m.month + 1)),
      RangePreset.last6Months =>
        DateSpan(DateTime(m.year, m.month - 5), DateTime(m.year, m.month + 1)),
      RangePreset.thisYear =>
        DateSpan(DateTime(now.year), DateTime(now.year + 1)),
      RangePreset.custom => DateSpan.month(now),
    };
  }
}

@immutable
class StatsRange {
  const StatsRange(this.preset, this.span);
  final RangePreset preset;
  final DateSpan span;
}

class StatsRangeController extends Notifier<StatsRange> {
  @override
  StatsRange build() {
    final now = ref.read(clockProvider)();
    return StatsRange(RangePreset.thisMonth, RangePreset.thisMonth.resolve(now));
  }

  void select(RangePreset preset) {
    final now = ref.read(clockProvider)();
    state = StatsRange(preset, preset.resolve(now));
  }

  void custom(DateSpan span) => state = StatsRange(RangePreset.custom, span);
}

final statsRangeProvider =
    NotifierProvider<StatsRangeController, StatsRange>(StatsRangeController.new);

@immutable
class MonthComparison {
  const MonthComparison({
    required this.current,
    required this.previous,
    required this.currentLabel,
    required this.previousLabel,
  });
  final Totals current;
  final Totals previous;
  final DateSpan currentLabel;
  final DateSpan previousLabel;

  double? get expenseChange =>
      FinanceCalculator.percentChange(previous.expense, current.expense);
  double? get incomeChange =>
      FinanceCalculator.percentChange(previous.income, current.income);
}

@immutable
class StatisticsData {
  const StatisticsData({
    required this.span,
    required this.totals,
    required this.flowBuckets,
    required this.flowBucketSize,
    required this.trend,
    required this.trendBucketSize,
    required this.categories,
    required this.averageDailyExpense,
    required this.comparison,
  });

  final DateSpan span;
  final Totals totals;
  final List<PeriodBucket> flowBuckets;
  final BucketSize flowBucketSize;
  final List<PeriodBucket> trend;
  final BucketSize trendBucketSize;
  final List<CategoryShare> categories;
  final int averageDailyExpense;
  final MonthComparison comparison;

  CategoryShare? get topCategory => categories.firstOrNull;
  bool get isEmpty => totals.count == 0;
}

final statisticsProvider = Provider<StatisticsData>((ref) {
  final txs = ref.watch(reportingTransactionsProvider);
  final span = ref.watch(statsRangeProvider).span;
  final now = ref.watch(clockProvider)();

  // Charts stop at today so future days don't render as misleading zeros.
  final tomorrow = Dates.addDays(Dates.dateOnly(now), 1);
  final chartSpan = span.end.isAfter(tomorrow) && span.start.isBefore(tomorrow)
      ? DateSpan(span.start, tomorrow)
      : span;
  final flowSize = FinanceCalculator.bucketFor(chartSpan);
  final trendSize = FinanceCalculator.bucketFor(chartSpan, forTrend: true);

  // Month comparison: the last month of the selected range vs. the month
  // before it (clamped to the current month for future-ending ranges).
  var anchor = span.lastDay;
  if (anchor.isAfter(now)) anchor = now;
  final cur = DateSpan.month(anchor);
  final prev = DateSpan.month(DateTime(anchor.year, anchor.month - 1));

  return StatisticsData(
    span: span,
    totals: FinanceCalculator.totals(txs, span: span),
    flowBuckets: FinanceCalculator.buckets(txs, chartSpan, flowSize),
    flowBucketSize: flowSize,
    trend: FinanceCalculator.buckets(txs, chartSpan, trendSize),
    trendBucketSize: trendSize,
    categories: FinanceCalculator.expenseByCategory(txs, span),
    averageDailyExpense:
        FinanceCalculator.averageDailyExpense(txs, span, now),
    comparison: MonthComparison(
      current: FinanceCalculator.totals(txs, span: cur),
      previous: FinanceCalculator.totals(txs, span: prev),
      currentLabel: cur,
      previousLabel: prev,
    ),
  );
});
