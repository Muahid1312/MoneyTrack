import '../../../core/utils/app_language.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/finance_hero.dart';
import '../../../core/widgets/progress.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/providers.dart';
import '../../budgets/application/budget_providers.dart';
import '../../budgets/domain/wallet_budget.dart';
import '../../budgets/presentation/budgets_overview_screen.dart';
import '../../groups/presentation/groups_screen.dart';
import '../../managed_funds/presentation/managed_funds_screen.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/upcoming_screen.dart';
import '../../settings/application/settings_controller.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../transactions/application/transaction_filter.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/ledger_screen.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallets_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeScreen> {
  DateTime? _selectedDay;

  Future<void> _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(clockProvider)();
    final currency = settings.currency;
    final material = MaterialLocalizations.of(context);
    final monthLabel = context.usesDari
        ? material.formatMonthYear(now)
        : DateFormat.MMM().format(now);
    final txState = ref.watch(transactionsProvider);
    final entries = ref.watch(reportingTransactionsProvider);
    final walletState = ref.watch(walletsProvider);
    final total = ref.watch(currencyBalancesProvider)[currency] ?? 0;
    final month = FinanceCalculator.totals(entries, span: DateSpan.month(now));
    final t = Theme.of(context).textTheme;
    final a = context.accent;
    final today = Dates.dateOnly(now);
    final first = periodStart(BudgetPeriod.weekly, today);
    final spent = FinanceCalculator.dailyExpenses(
      entries.where((tx) => !tx.occurredAt.isAfter(now)),
      first,
      7,
    );
    final due = dueItems(ref.watch(planningProvider).valueOrNull);
    final loading = txState.isLoading || walletState.isLoading;
    final failed = txState.hasError || walletState.hasError;
    String money(int minor) =>
        settings.hideBalance ? '••••' : Money.format(minor, currency);
    final name = settings.userName.trim();
    final greeting = now.hour < 12
        ? context.tr('Good morning', 'صبح بخیر')
        : now.hour < 18
        ? context.tr('Good afternoon', 'روز بخیر')
        : context.tr('Good evening', 'شام بخیر');
    void history() {
      ref.read(activityCurrencyChoiceProvider.notifier).state = null;
      ref.read(transactionFilterProvider.notifier).state =
          const TransactionFilter();
      _open(const LedgerScreen());
    }

    Future<void> day(DateTime date) async {
      setState(() => _selectedDay = date);
      final previousCurrency = ref.read(activityCurrencyChoiceProvider);
      final previousFilter = ref.read(transactionFilterProvider);
      ref.read(activityCurrencyChoiceProvider.notifier).state = currency;
      ref.read(transactionFilterProvider.notifier).state = TransactionFilter(
        type: TransactionType.expense,
        date: DateFilter.custom,
        customSpan: DateSpan(date, Dates.addDays(date, 1)),
      );
      await _open(
        Scaffold(
          appBar: AppBar(title: Text(material.formatMediumDate(date))),
          body: const TransactionsScreen(),
        ),
      );
      if (mounted) {
        ref.read(activityCurrencyChoiceProvider.notifier).state =
            previousCurrency;
        ref.read(transactionFilterProvider.notifier).state = previousFilter;
      }
    }

    final shortcuts = <({String name, IconData icon, VoidCallback open})>[
      (
        name: 'Expense',
        icon: Icons.remove_circle_outline,
        open: () => TransactionActions.openEditor(
          context,
          ref,
          initialType: TransactionType.expense,
        ),
      ),
      (
        name: 'Income',
        icon: Icons.add_circle_outline,
        open: () => TransactionActions.openEditor(
          context,
          ref,
          initialType: TransactionType.income,
        ),
      ),
      (
        name: 'Transfer',
        icon: Icons.swap_horiz,
        open: () => _open(const TransferScreen()),
      ),
      (
        name: 'Group Funds',
        icon: Icons.groups_outlined,
        open: () => _open(const GroupsScreen()),
      ),
      (
        name: 'Managed Funds',
        icon: Icons.inventory_2_outlined,
        open: () => _open(const ManagedFundsScreen()),
      ),
    ];
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('moneytrack-home'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? greeting : '$greeting, $name',
                      style: t.headlineMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr(
                        'Welcome to MoneyTrack',
                        'به مانی‌ترک خوش آمدید',
                      ),
                      style: t.bodyMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: a.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: due.isEmpty
                      ? 'Upcoming obligations'
                      : 'Upcoming obligations (${due.length})',
                  onPressed: () => _open(const UpcomingScreen()),
                  icon: Badge(
                    isLabelVisible: due.isNotEmpty,
                    child: Icon(
                      Icons.notifications_none_outlined,
                      color: a.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (failed || loading)
            AppCard(
              child: failed
                  ? TextButton(
                      onPressed: () {
                        ref.invalidate(transactionsProvider);
                        ref.invalidate(walletsProvider);
                      },
                      child: const Text('Retry loading balances'),
                    )
                  : const LinearProgressIndicator(),
            )
          else
            FinanceHero(
              label:
                  '${context.tr('Total personal balance', 'مجموع موجودی شخصی')} · ${currency.code}',
              amount: money(total),
              action: IconButton(
                tooltip: settings.hideBalance ? 'Show balance' : 'Hide balance',
                onPressed: () =>
                    ref.read(settingsProvider.notifier).toggleHideBalance(),
                icon: Icon(
                  settings.hideBalance
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: a.cardInk,
                ),
              ),
              details: [
                (
                  label: '${context.tr('Income', 'عاید')} · $monthLabel',
                  value: money(month.income),
                ),
                (
                  label: '${context.tr('Expenses', 'مصارف')} · $monthLabel',
                  value: money(month.expense),
                ),
              ],
            ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final columns =
                  box.maxWidth >= 347 &&
                      MediaQuery.textScalerOf(context).scale(13) < 17
                  ? 5
                  : 3;
              const gap = 5.0;
              final width = (box.maxWidth - (columns - 1) * gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 6,
                children: [
                  for (final shortcut in shortcuts)
                    SizedBox(
                      width: width,
                      child: Tooltip(
                        message:
                            shortcut.name == 'Expense' ||
                                shortcut.name == 'Income'
                            ? 'Add ${shortcut.name.toLowerCase()}'
                            : shortcut.name,
                        child: InkWell(
                          onTap: shortcut.open,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              children: [
                                Material(
                                  color: a.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: SizedBox.square(
                                    dimension: 43,
                                    child: Icon(
                                      shortcut.icon,
                                      color: a.onSurface,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  switch (shortcut.name) {
                                    'Expense' => context.tr('Expense', 'مصرف'),
                                    'Income' => context.tr('Income', 'عاید'),
                                    'Transfer' => context.tr(
                                      'Transfer',
                                      'انتقال',
                                    ),
                                    'Group Funds' => context.tr(
                                      'Group Funds',
                                      'پول گروهی',
                                    ),
                                    _ => context.tr(
                                      'Managed Funds',
                                      'پول امانتی',
                                    ),
                                  },
                                  textAlign: TextAlign.center,
                                  style: t.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _WeekCard(
            first: first,
            today: today,
            selected: _selectedDay ?? today,
            amounts: spent,
            currency: currency,
            hidden: settings.hideBalance,
            onDay: day,
          ),
          const SizedBox(height: 18),
          SectionHeader(
            title: context.tr('Budgets', 'بودجه‌ها'),
            actionLabel: context.tr('View all', 'نمایش همه'),
            onAction: () => _open(const BudgetsOverviewScreen()),
          ),
          const SizedBox(height: 8),
          _HomeBudgets(
            currency: currency,
            now: now,
            hidden: settings.hideBalance,
          ),
          const SizedBox(height: 18),
          SectionHeader(
            title: context.tr('Recent transactions', 'معاملات اخیر'),
            actionLabel: context.tr('See all', 'نمایش همه'),
            onAction: history,
          ),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: [
                if (entries.isEmpty)
                  const ListTile(title: Text('No transactions yet')),
                for (final tx in entries.take(4))
                  if (!settings.hideBalance)
                    TransactionTile(
                      transaction: tx,
                      currency: tx.currency,
                      onTap: () =>
                          TransactionActions.showActions(context, ref, tx),
                    )
                  else
                    ListTile(
                      leading: CategoryAvatar(category: tx.category, size: 36),
                      title: Text(tx.title),
                      subtitle: Text(tx.category.name),
                      trailing: const Text('••••'),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.first,
    required this.today,
    required this.selected,
    required this.amounts,
    required this.currency,
    required this.hidden,
    required this.onDay,
  });
  final DateTime first, today, selected;
  final List<int> amounts;
  final AppCurrency currency;
  final bool hidden;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final a = context.accent, p = context.palette;
    final material = MaterialLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final max = amounts.fold<int>(1, math.max);
    final bar = AppAccent.readable(
      Color.lerp(p.surface, a.primary, .48)!,
      p.surface,
      ratio: 3,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Weekly spending', 'مصارف هفته'),
            style: t.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            hidden
                ? '••••'
                : Money.format(
                    amounts.fold(0, (sum, amount) => sum + amount),
                    currency,
                  ),
            textDirection: TextDirection.ltr,
            style: AppTypography.amount(25, color: p.textPrimary),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final width = math.max(44.0, box.maxWidth / 7);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Builder(
                        builder: (context) {
                          final d = Dates.addDays(first, i);
                          final active = Dates.isSameDay(d, selected);
                          final muted = d.isAfter(today);
                          return SizedBox(
                            width: width,
                            child: Semantics(
                              selected: active,
                              child: InkWell(
                                onTap: muted ? null : () => onDay(d),
                                borderRadius: BorderRadius.circular(10),
                                child: Tooltip(
                                  message:
                                      '${material.formatMediumDate(d)} · ${hidden ? '••••' : Money.format(amounts[i], currency)}',
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: 74,
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            height: hidden || amounts[i] == 0
                                                ? 5
                                                : 6 + 68 * amounts[i] / max,
                                            width: math.min(22.0, width * .52),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? a.primary
                                                  : muted
                                                  ? p.chartTrack
                                                  : bar,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          context.usesDari
                                              ? const [
                                                  'دوش',
                                                  'سه',
                                                  'چهار',
                                                  'پنج',
                                                  'جمعه',
                                                  'شنبه',
                                                  'یک',
                                                ][i]
                                              : DateFormat.E().format(d),
                                          style: t.labelSmall?.copyWith(
                                            color: active
                                                ? a.primary
                                                : p.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeBudgets extends ConsumerWidget {
  const _HomeBudgets({
    required this.currency,
    required this.now,
    required this.hidden,
  });
  final AppCurrency currency;
  final DateTime now;
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = ref.watch(planningProvider);
    final entries = ref.watch(reportingTransactionsProvider);
    final wallets = ref.watch(walletsProvider).valueOrNull?.wallets ?? [];
    final ids = wallets
        .where((w) => w.currency == currency && !w.archived)
        .map((w) => w.id)
        .toSet();
    final budget = ref.watch(budgetStatusProvider);
    final rows = <({String name, int spent, int limit, IconData icon})>[];
    for (final plan in from.valueOrNull?.budgets ?? const <WalletBudget>[]) {
      if (!ids.contains(plan.walletId)) continue;
      final value = plan.status(now, currency, entries);
      if (value == null) continue;
      rows.add((
        name: plan.category == null
            ? 'All expenses'
            : Categories.byId(plan.category!).name,
        spent: value.spent,
        limit: plan.limit + value.carry,
        icon: plan.category == null
            ? Icons.donut_large
            : Categories.byId(plan.category!).icon,
      ));
      if (rows.length >= 2) break;
    }
    if (rows.isEmpty && budget.hasBudget) {
      rows.add((
        name: context.tr('Monthly spending limit', 'حد مصرف ماهانه'),
        spent: budget.spentMinor,
        limit: budget.budgetMinor,
        icon: Icons.donut_large,
      ));
    }
    return AppCard(
      child: Column(
        children: [
          if (rows.isEmpty)
            Text(
              context.tr(
                'No active budget in this currency.',
                'برای این واحد پول بودجهٔ فعال وجود ندارد.',
              ),
            ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(row.icon, color: context.accent.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (!hidden) ...[
                          Text(
                            '${Money.format(row.spent, currency)} ${context.tr('of', 'از')} ${Money.format(row.limit, currency)}',
                          ),
                          const SizedBox(height: 5),
                          AnimatedProgressBar(
                            value: row.spent / row.limit,
                            color: budgetColor(context, row.spent / row.limit),
                            height: 6,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
