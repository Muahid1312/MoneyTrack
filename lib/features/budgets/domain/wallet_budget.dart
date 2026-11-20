import 'dart:math' as math;

import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../data/models/transaction.dart';
import '../../planning/domain/schedule.dart';

enum BudgetPeriod { daily, weekly, monthly, custom }

DateTime periodStart(BudgetPeriod period, DateTime day) => switch (period) {
  BudgetPeriod.monthly => DateTime(day.year, day.month),
  BudgetPeriod.weekly => DateTime(
    day.year,
    day.month,
    day.day - day.weekday + 1,
  ),
  _ => DateTime(day.year, day.month, day.day),
};

class WalletBudget {
  const WalletBudget({
    this.id,
    required this.walletId,
    required this.period,
    required this.limit,
    required this.start,
    this.end,
    this.category,
    this.rollover = false,
  });
  final int? id;
  final int walletId, limit;
  final BudgetPeriod period;
  final DateTime start;
  final DateTime? end;
  final String? category;
  final bool rollover;

  factory WalletBudget.fromRow(Map<String, Object?> row) => WalletBudget(
    id: row['id'] as int,
    walletId: row['wallet_id'] as int,
    period: BudgetPeriod.values.byName(row['period'] as String),
    limit: row['limit_minor'] as int,
    start: CivilSchedule.parse(row['start_date'] as String),
    end: row['end_date'] == null
        ? null
        : CivilSchedule.parse(row['end_date'] as String),
    category: row['category_id'] as String?,
    rollover: row['rollover'] == 1,
  );

  void validate() {
    if (limit <= 0 ||
        limit > AppInfo.maxAmountMinor ||
        (category != null &&
            !Categories.expense.any((c) => c.id == category)) ||
        (period == BudgetPeriod.custom
            ? end == null || end!.isBefore(start) || rollover
            : end != null || start != periodStart(period, start))) {
      throw const FormatException('Invalid budget settings');
    }
  }

  Map<String, Object?> toRow() => {
    'wallet_id': walletId,
    'period': period.name,
    'limit_minor': limit,
    'category_id': category,
    'start_date': CivilSchedule.key(start),
    'end_date': end == null ? null : CivilSchedule.key(end!),
    'rollover': rollover ? 1 : 0,
  };

  // UTC civil day numbers avoid 23/25-hour local days at DST transitions.
  int _index(DateTime day) {
    if (period == BudgetPeriod.custom) return 0;
    if (period == BudgetPeriod.monthly) {
      return (day.year - start.year) * 12 + day.month - start.month;
    }
    final days = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return period == BudgetPeriod.weekly ? days ~/ 7 : days;
  }

  ({int spent, int carry, int remaining})? status(
    DateTime now,
    AppCurrency currency,
    Iterable<TransactionModel> entries,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(start) || (end != null && today.isAfter(end!))) {
      return null;
    }
    final current = _index(today);
    final totals = <int, int>{};
    for (final tx in entries) {
      if (tx.walletId != walletId ||
          tx.currency != currency ||
          tx.type.isIncome ||
          (category != null && tx.categoryId != category) ||
          tx.occurredAt.isBefore(start) ||
          tx.occurredAt.isAfter(now)) {
        continue;
      }
      final index = _index(tx.occurredAt);
      totals[index] = (totals[index] ?? 0) + tx.amountMinor;
    }
    var carry = 0;
    if (rollover) {
      var next = 0;
      for (final index
          in totals.keys.where((i) => i < current).toList()..sort()) {
        carry = math.max(
          0,
          carry + (index - next + 1) * limit - totals[index]!,
        );
        next = index + 1;
      }
      carry += (current - next) * limit;
    }
    final spent = totals[current] ?? 0;
    return (spent: spent, carry: carry, remaining: limit + carry - spent);
  }
}
