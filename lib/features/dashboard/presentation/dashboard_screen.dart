import '../../transactions/application/transaction_filter.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/upcoming_screen.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../explore/explore_screen.dart';
import '../../../core/utils/money.dart';
import 'widgets/dashboard_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_shell.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/providers.dart';
import '../../budgets/application/budget_providers.dart';
import '../../budgets/presentation/wallet_budget_panel.dart';
import '../../budgets/presentation/budget_editor_sheet.dart';
import '../../budgets/presentation/budget_screen.dart';
import '../../budgets/presentation/widgets/budget_widgets.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../application/dashboard_providers.dart';
import 'widgets/balance_card.dart';
import 'widgets/weekly_spending_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final currency = settings.currency;
    final summary = ref.watch(dashboardSummaryProvider);

    final budget = ref.watch(budgetStatusProvider);
    final wallet = ref.watch(selectedWalletProvider);
    final recent = wallet == null
        ? summary.recent
        : ref
              .watch(allTransactionsProvider)
              .where((tx) => tx.walletId == wallet.id)
              .take(3)
              .toList();
    final marker = ref.watch(lastChangedTransactionProvider);
    final now = ref.watch(clockProvider)();
    final due = dueItems(ref.watch(planningProvider).valueOrNull);
    final homeCurrency = wallet?.currency ?? currency;
    final totals = FinanceCalculator.totals(
      ref
          .watch(allTransactionsProvider)
          .where((t) => t.currency == homeCurrency),
      span: DateSpan.month(now),
    );
    String amount(int n) =>
        settings.hideBalance ? '••••' : Money.format(n, homeCurrency);
    final name = settings.userName.trim();

    void openBudget() => Navigator.of(context).push(BudgetScreen.route());

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.lg,
              AppSpacing.screen,
              AppShell.contentBottomInset(context),
            ),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Today' : 'Hello, $name',
                        style: t.headlineMedium,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Wallets'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WalletsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                WalletBudgetPanel(
                  actions: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _QuickAction(
                              label: 'Add expense',
                              icon: Icons.north_east_rounded,
                              color: p.expense,
                              background: p.expenseSoft,
                              onTap: () => TransactionActions.openEditor(
                                context,
                                ref,
                                initialType: TransactionType.expense,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _QuickAction(
                              label: 'Add income',
                              icon: Icons.south_west_rounded,
                              color: p.income,
                              background: p.incomeSoft,
                              onTap: () => TransactionActions.openEditor(
                                context,
                                ref,
                                initialType: TransactionType.income,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Transfer money'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const TransferScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionHeader(
                  title: DateFormat('MMMM y').format(now),
                  subtitle: 'All wallets · ${homeCurrency.code}',
                ),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ref.watch(transactionsProvider).hasError)
                        TextButton(
                          onPressed: () => ref.invalidate(transactionsProvider),
                          child: const Text('Retry monthly totals'),
                        )
                      else if (ref.watch(transactionsProvider).isLoading)
                        const LinearProgressIndicator()
                      else ...[
                        Text(
                          'Income   ${amount(totals.income)}',
                          style: t.titleMedium?.copyWith(color: p.income),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Expenses   ${amount(totals.expense)}',
                          style: t.titleMedium,
                        ),
                      ],
                      if (budget.hasBudget)
                        TextButton(
                          onPressed: openBudget,
                          child: Text(
                            'Monthly budget · ${currency.code} · ${settings.hideBalance ? "••••" : Money.format(budget.remainingMinor.abs(), currency)} ${budget.remainingMinor < 0 ? "over" : "left"}',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SectionHeader(
                  title: 'Recent activity',
                  actionLabel: 'View activity',
                  onAction: () {
                    ref.read(activityCurrencyChoiceProvider.notifier).state =
                        wallet?.currency ?? currency;
                    ref.read(transactionFilterProvider.notifier).state =
                        TransactionFilter(walletId: wallet?.id);
                    Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('Wallet activity')),body:const TransactionsScreen())));
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppDurations.medium,
                    child: recent.isEmpty
                        ? EmptyState(
                            key: const ValueKey('empty'),
                            compact: true,
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'Start tracking',
                            message:
                                'Record an expense or income for this wallet.',
                            actionLabel: 'Add transaction',
                            onAction: () =>
                                TransactionActions.openEditor(context, ref),
                          )
                        : Column(
                            key: const ValueKey('list'),
                            children: [
                              for (final tx in recent)
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(tx.id),
                                  tween: Tween(
                                    begin: isFreshChange(marker, tx.id) ? 0 : 1,
                                    end: 1,
                                  ),
                                  duration: AppDurations.slow,
                                  curve: AppCurves.standard,
                                  builder: (context, v, child) => Opacity(
                                    opacity: v,
                                    child: Transform.translate(
                                      offset: Offset(0, -10 * (1 - v)),
                                      child: child,
                                    ),
                                  ),
                                  child: TransactionTile(
                                    transaction: tx,
                                    currency: tx.currency,
                                    showDate: !Dates.isSameDay(
                                      tx.occurredAt,
                                      now,
                                    ),
                                    highlight: isFreshChange(marker, tx.id),
                                    onTap: () => TransactionActions.showActions(
                                      context,
                                      ref,
                                      tx,
                                    ),
                                    onLongPress: () =>
                                        TransactionActions.showActions(
                                          context,
                                          ref,
                                          tx,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (due.isNotEmpty) ...[
                  const SectionHeader(title: 'Next due'),
                  Card(child: DueTile(due.first)),
                ],
                if (ref.watch(allTransactionsProvider).isEmpty)
                  TextButton.icon(
                    onPressed: () => showQuickGuide(context),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Getting started'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: true,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.control,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthlyOverviewScreen extends ConsumerWidget {
  const MonthlyOverviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final settings = ref.watch(settingsProvider);
    final currency = settings.currency;
    final budget = ref.watch(budgetStatusProvider);
    final weekly = ref.watch(weeklySpendingProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final period = ref.watch(dashboardPeriodProvider);
    void openBudget() => Navigator.push(context, BudgetScreen.route());
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly overview')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: ref.watch(dashboardMonthOffsetProvider),
            decoration: const InputDecoration(
              labelText: 'Income & expense period',
              prefixIcon: Icon(Icons.date_range_outlined),
            ),
            items: [
              for (final offset in [0, -1, -2])
                DropdownMenuItem(
                  value: offset,
                  child: Text(
                    DateFormat(
                      'MMMM y',
                    ).format(DateTime(now.year, now.month + offset)),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(dashboardMonthOffsetProvider.notifier).state = value;
              }
            },
          ),
          const SizedBox(height: 16),
          if (ref.watch(transactionsProvider).hasError)
            AppCard(
              child: Column(
                children: [
                  const Text('Could not load transaction summaries'),
                  TextButton(
                    onPressed: () => ref.invalidate(transactionsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (ref.watch(walletRepositoryProvider) != null &&
              ref.watch(walletsProvider).hasError)
            AppCard(
              child: Column(
                children: [
                  const Text('Could not load wallet balances'),
                  TextButton(
                    onPressed: () => ref.invalidate(walletsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (ref.watch(walletRepositoryProvider) != null &&
              ref.watch(walletsProvider).valueOrNull == null)
            const Center(child: CircularProgressIndicator())
          else
            BalanceCard(
              balanceMinor: summary.balanceMinor,
              month: summary.month,
              previousMonth: summary.previousMonth,
              currency: currency,
              hidden: settings.hideBalance,
              onToggleHidden: () =>
                  ref.read(settingsProvider.notifier).toggleHideBalance(),
              monthLabel: DateFormat('MMM y').format(period),
            ),
          const SizedBox(height: AppSpacing.lg),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Weekly spending',
            subtitle: 'Tap a bar for details',
          ),
          const SizedBox(height: AppSpacing.md),
          WeeklySpendingCard(data: weekly, currency: currency),

          const SizedBox(height: AppSpacing.xxl),
          SectionHeader(
            title: 'Budget',
            subtitle: DateFormat('MMMM y').format(now),
            actionLabel: budget.hasBudget ? 'Details' : null,
            onAction: budget.hasBudget ? openBudget : null,
          ),
          const SizedBox(height: AppSpacing.md),
          BudgetSummaryCard(
            status: budget,
            currency: currency,
            onOpen: openBudget,
            onSetBudget: () => showBudgetEditor(context),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const DashboardContext(),
        ],
      ),
    );
  }
}
