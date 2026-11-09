import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../wallets/application/wallet_providers.dart';

final dashboardMonthOffsetProvider = StateProvider<int>((ref) => 0);
final dashboardPeriodProvider = Provider<DateTime>((ref) {
  final now=ref.watch(clockProvider)();
  return DateTime(now.year,now.month+ref.watch(dashboardMonthOffsetProvider));
});

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.balanceMinor,
    required this.month,
    required this.previousMonth,
    required this.recent,
  });
  final int balanceMinor;
  final Totals month;
  final Totals previousMonth;
  final List<TransactionModel> recent;
}

final dashboardSummaryProvider = Provider<DashboardSummary>((ref) {
  final txs = ref.watch(reportingTransactionsProvider);
  final now = ref.watch(dashboardPeriodProvider);
  final prev = DateTime(now.year, now.month - 1);
  return DashboardSummary(
    balanceMinor: ref.watch(currencyBalancesProvider)[ref.watch(currencyProvider)] ?? 0,
    month: FinanceCalculator.totals(txs, span: DateSpan.month(now)),
    previousMonth: FinanceCalculator.totals(txs, span: DateSpan.month(prev)),
    recent: txs.take(5).toList(),
  );
});

@immutable
class WeeklySpending {
  const WeeklySpending({
    required this.days,
    required this.amounts,
    required this.total,
    required this.previousTotal,
  });

  /// Seven calendar days ending today (oldest first).
  final List<DateTime> days;
  final List<int> amounts;
  final int total;
  final int previousTotal;
}

final weeklySpendingProvider = Provider<WeeklySpending>((ref) {
  final txs = ref.watch(reportingTransactionsProvider);
  final today = Dates.dateOnly(ref.watch(clockProvider)());
  final first = Dates.addDays(today, -6);
  final amounts = FinanceCalculator.dailyExpenses(txs, first, 7);
  final prev =
      FinanceCalculator.dailyExpenses(txs, Dates.addDays(first, -7), 7);
  return WeeklySpending(
    days: [for (var i = 0; i < 7; i++) Dates.addDays(first, i)],
    amounts: amounts,
    total: amounts.fold(0, (a, b) => a + b),
    previousTotal: prev.fold(0, (a, b) => a + b),
  );
});
