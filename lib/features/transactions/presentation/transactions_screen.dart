import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../application/transaction_filter.dart';
import '../application/transactions_controller.dart';
import 'transaction_actions.dart';
import 'widgets/filter_sheets.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  /// Ids swiped away (hidden immediately while the delete completes).
  final Set<int> _dismissed = {};
  int _revision = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    setState(() {}); // update clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final f = ref.read(transactionFilterProvider);
      ref.read(transactionFilterProvider.notifier).state = f.copyWith(query: v);
    });
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    ref.read(transactionFilterProvider.notifier).state = const TransactionFilter();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final currency = ref.watch(currencyProvider);
    final filter = ref.watch(transactionFilterProvider);
    final data = ref.watch(filteredTransactionsProvider);
    final totalCount = ref.watch(reportingTransactionsProvider).length;
    final marker = ref.watch(lastChangedTransactionProvider);
    final now = ref.watch(clockProvider)();

    final rows = ref.watch(historyRowsProvider);
    final presentIds = data.groups.expand((g) => g.items).map((t) => t.id).toSet();
    _dismissed.removeWhere((id) => !presentIds.contains(id));

    return GestureDetector(
      onTap: () => _searchFocus.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transactions', style: t.headlineMedium),
                    Text('${currency.code} only · change reporting currency in Settings', style: t.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      totalCount == 0
                          ? 'Your history will appear here'
                          : '$totalCount ${totalCount == 1 ? 'entry' : 'entries'} recorded',
                      style: t.bodyMedium?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _searchField(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _filterChips(filter)),
          if (ref.watch(transactionsProvider).hasError) SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20), child: Column(children: [
              const Text('Transaction history could not be loaded.'),
              TextButton(onPressed: () => ref.invalidate(transactionsProvider), child: const Text('Retry')),
            ]))),
          if (filter.isActive && data.count > 0)
            SliverToBoxAdapter(child: _summary(data, currency)),
          if (totalCount == 0)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppShell.contentBottomInset(context)),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message:
                      'Record your first income or expense and it will show up here, grouped by day.',
                  actionLabel: 'Add transaction',
                  onAction: () => TransactionActions.openEditor(context, ref),
                ),
              ),
            )
          else if (data.count == 0)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppShell.contentBottomInset(context)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'Try a different search term or loosen your filters.',
                    ),
                    SecondaryButton(
                      label: 'Clear filters',
                      icon: Icons.filter_alt_off_outlined,
                      expanded: false,
                      onPressed: _clearFilters,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
                  AppSpacing.screen, AppShell.contentBottomInset(context)),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  if (row.group != null) return _HistoryHeader(group: row.group!, now: now, currency: currency);
                  final tx = row.transaction!;
                  if (_dismissed.contains(tx.id)) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(bottom: 4), child: Material(
                    color: p.surface, borderRadius: AppRadii.control,
                    child: Dismissible(key: ValueKey('tx-${tx.id}-$_revision'), direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => TransactionActions.askDelete(context, tx, currency),
                      onDismissed: (_) async {
                        setState(() => _dismissed.add(tx.id!));
                        final deleted = await TransactionActions.deleteWithUndo(context, ref, tx);
                        if (!deleted && mounted) setState(() { _dismissed.remove(tx.id); _revision++; });
                      },
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(color: p.expenseSoft, borderRadius: AppRadii.control),
                        child: Icon(Icons.delete_outline_rounded, color: p.expense)),
                      child: TransactionTile(transaction: tx, currency: currency,
                        highlight: isFreshChange(marker, tx.id),
                        onTap: () => TransactionActions.openEditor(context, ref, existing: tx),
                        onLongPress: () => TransactionActions.showActions(context, ref, tx)),
                    ),
                  ));
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final palette = context.palette;
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      onChanged: _onSearch,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search description or category',
        fillColor: palette.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: palette.border),
        ),
        prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary, size: 22),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
                onPressed: () {
                  _search.clear();
                  _onSearch('');
                },
              ),
      ),
    );
  }

  Widget _filterChips(TransactionFilter f) {
    final notifier = ref.read(transactionFilterProvider.notifier);
    String categoryLabel() {
      if (f.categoryIds.isEmpty) return 'Category';
      if (f.categoryIds.length == 1) return Categories.byId(f.categoryIds.first).name;
      return '${f.categoryIds.length} categories';
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          AppChip(
            label: 'All',
            selected: f.type == null,
            onTap: () => notifier.state = f.copyWith(type: () => null),
          ),
          const SizedBox(width: 8),
          AppChip(
            label: 'Income',
            icon: Icons.south_west_rounded,
            selected: f.type == TransactionType.income,
            onTap: () => notifier.state = f.copyWith(
                type: () => f.type == TransactionType.income ? null : TransactionType.income),
          ),
          const SizedBox(width: 8),
          AppChip(
            label: 'Expenses',
            icon: Icons.north_east_rounded,
            selected: f.type == TransactionType.expense,
            onTap: () => notifier.state = f.copyWith(
                type: () => f.type == TransactionType.expense ? null : TransactionType.expense),
          ),
          const SizedBox(width: 8),
          AppChip(
            label: categoryLabel(),
            icon: Icons.category_outlined,
            trailingIcon: Icons.expand_more_rounded,
            selected: f.categoryIds.isNotEmpty,
            onTap: () async {
              final picked = await showCategoryFilterSheet(context, f.categoryIds);
              if (picked != null) {
                notifier.state = ref.read(transactionFilterProvider).copyWith(categoryIds: picked);
              }
            },
          ),
          const SizedBox(width: 8),
          AppChip(
            label: f.date == DateFilter.custom && f.customSpan != null
                ? Dates.spanLabel(f.customSpan!)
                : (f.date == DateFilter.all ? 'Date' : f.date.label),
            icon: Icons.calendar_today_rounded,
            trailingIcon: Icons.expand_more_rounded,
            selected: f.date != DateFilter.all,
            onTap: () async {
              final picked = await showDateFilterSheet(context, f);
              if (picked != null) notifier.state = picked;
            },
          ),
          if (f.hasActiveFilters) ...[
            const SizedBox(width: 8),
            AppChip(
              label: 'Reset',
              icon: Icons.close_rounded,
              selected: false,
              onTap: _clearFilters,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(FilteredTransactions d, AppCurrency currency) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    Widget cell(String label, int value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelSmall?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Money.format(value, currency),
                    style: AppTypography.amount(15, color: color)),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, 0),
      child: AnimatedContainer(
        duration: AppDurations.medium,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            cell('${d.count} RESULTS', d.income - d.expense, p.textPrimary),
            cell('MONEY IN', d.income, p.income),
            cell('MONEY OUT', d.expense, p.expense),
          ],
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.group, required this.now, required this.currency});
  final TransactionGroup group; final DateTime now; final AppCurrency currency;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
      Text(Dates.relativeDay(group.day, now), style: Theme.of(context).textTheme.labelLarge),
      Text(Money.format(group.net, currency, signed: true), style: AppTypography.amount(12.5, color: context.palette.textSecondary)),
    ]));
}
