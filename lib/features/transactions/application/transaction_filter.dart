import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/providers.dart';
import '../../wallets/application/wallet_providers.dart';

enum DateFilter {
  all('Any time'),
  thisWeek('Last 7 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  custom('Custom range');

  const DateFilter(this.label);
  final String label;
}

@immutable
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.type,
    this.categoryIds = const {},
    this.date = DateFilter.all,
    this.customSpan,
  });

  final String query;
  final TransactionType? type;
  final Set<String> categoryIds;
  final DateFilter date;
  final DateSpan? customSpan;

  bool get hasActiveFilters =>
      type != null || categoryIds.isNotEmpty || date != DateFilter.all;
  bool get isActive => hasActiveFilters || query.trim().isNotEmpty;

  int get activeCount =>
      (type != null ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (date != DateFilter.all ? 1 : 0);

  DateSpan? resolveSpan(DateTime now) => switch (date) {
        DateFilter.all => null,
        DateFilter.thisWeek => DateSpan.lastDays(now, 7),
        DateFilter.thisMonth => DateSpan.month(now),
        DateFilter.lastMonth => DateSpan.month(DateTime(now.year, now.month - 1)),
        DateFilter.custom => customSpan,
      };

  bool matches(TransactionModel t, DateSpan? span) {
    if (type != null && t.type != type) return false;
    if (categoryIds.isNotEmpty && !categoryIds.contains(t.categoryId)) {
      return false;
    }
    if (span != null && !span.contains(t.occurredAt)) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${t.note} ${t.category.name}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  TransactionFilter copyWith({
    String? query,
    TransactionType? Function()? type,
    Set<String>? categoryIds,
    DateFilter? date,
    DateSpan? Function()? customSpan,
  }) =>
      TransactionFilter(
        query: query ?? this.query,
        type: type != null ? type() : this.type,
        categoryIds: categoryIds ?? this.categoryIds,
        date: date ?? this.date,
        customSpan: customSpan != null ? customSpan() : this.customSpan,
      );
}

final transactionFilterProvider =
    StateProvider<TransactionFilter>((ref) => const TransactionFilter());

@immutable
class TransactionGroup {
  const TransactionGroup(this.day, this.items);
  final DateTime day;
  final List<TransactionModel> items;
  int get net => items.fold(0, (s, t) => s + t.signedMinor);
}

@immutable
class FilteredTransactions {
  const FilteredTransactions(this.groups, this.income, this.expense, this.count);
  final List<TransactionGroup> groups;
  final int income;
  final int expense;
  final int count;
}

final filteredTransactionsProvider = Provider<FilteredTransactions>((ref) {
  final all = ref.watch(reportingTransactionsProvider);
  final filter = ref.watch(transactionFilterProvider);
  final span = filter.resolveSpan(ref.watch(clockProvider)());

  final groups = <TransactionGroup>[];
  var income = 0, expense = 0, count = 0;
  for (final t in all) {
    if (!filter.matches(t, span)) continue;
    count++;
    if (t.type.isIncome) {
      income += t.amountMinor;
    } else {
      expense += t.amountMinor;
    }
    final day = Dates.dateOnly(t.occurredAt);
    if (groups.isEmpty || groups.last.day != day) {
      groups.add(TransactionGroup(day, [t]));
    } else {
      groups.last.items.add(t);
    }
  }
  return FilteredTransactions(groups, income, expense, count);
});

@immutable
class HistoryRow {
  const HistoryRow.header(this.group) : transaction = null;
  const HistoryRow.entry(this.transaction) : group = null;
  final TransactionGroup? group;
  final TransactionModel? transaction;
}

/// Flatten days and entries so a single busy day cannot eagerly build thousands
/// of transaction tiles. SliverList creates only visible rows.
final historyRowsProvider = Provider<List<HistoryRow>>((ref) => [
  for (final group in ref.watch(filteredTransactionsProvider).groups) ...[
    HistoryRow.header(group),
    for (final entry in group.items) HistoryRow.entry(entry),
  ],
]);
