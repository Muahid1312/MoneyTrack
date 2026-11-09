import 'package:flutter/foundation.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';
import '../../statistics/domain/finance_calculator.dart';

enum BudgetLevel { notSet, healthy, approaching, exceeded }

@immutable
class BudgetStatus {
  const BudgetStatus({
    required this.budgetMinor,
    required this.spentMinor,
    required this.month,
    required this.daysLeft,
    required this.daysInMonth,
    required this.categories,
  });

  final int budgetMinor;
  final int spentMinor;
  final DateSpan month;

  /// Days remaining in the month, including today.
  final int daysLeft;
  final int daysInMonth;
  final List<CategoryShare> categories;

  bool get hasBudget => budgetMinor > 0;
  int get remainingMinor => budgetMinor - spentMinor;
  int get overspentMinor => remainingMinor < 0 ? -remainingMinor : 0;

  /// spent / budget (unclamped, display only).
  double get ratio => hasBudget ? spentMinor / budgetMinor : 0;

  /// Safe amount per remaining day to stay on budget.
  int get dailyAllowanceMinor =>
      remainingMinor <= 0 || daysLeft <= 0 ? 0 : remainingMinor ~/ daysLeft;

  /// Linear projection of month-end spending.
  int get projectedMinor {
    final elapsed = daysInMonth - daysLeft + 1;
    if (elapsed <= 0) return spentMinor;
    return (spentMinor * daysInMonth * 2 + elapsed) ~/ (elapsed * 2);
  }

  BudgetLevel get level {
    if (!hasBudget) return BudgetLevel.notSet;
    if (spentMinor > budgetMinor) return BudgetLevel.exceeded;
    if (spentMinor * 100 >= budgetMinor * 80) return BudgetLevel.approaching;
    return BudgetLevel.healthy;
  }
}

abstract final class BudgetCalculator {
  static BudgetStatus compute({
    required int budgetMinor,
    required Iterable<TransactionModel> transactions,
    required DateTime now,
  }) {
    final month = DateSpan.month(now);
    final totals = FinanceCalculator.totals(transactions, span: month);
    final dim = Dates.daysInMonth(now);
    return BudgetStatus(
      budgetMinor: budgetMinor,
      spentMinor: totals.expense,
      month: month,
      daysLeft: dim - now.day + 1,
      daysInMonth: dim,
      categories: FinanceCalculator.expenseByCategory(transactions, month),
    );
  }
}
