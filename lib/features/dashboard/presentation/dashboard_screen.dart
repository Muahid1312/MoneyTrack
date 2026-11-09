import '../../transactions/presentation/transactions_screen.dart';
import 'widgets/dashboard_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_shell.dart';
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
import '../../budgets/domain/budget_calculator.dart';
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
    final weekly = ref.watch(weeklySpendingProvider);
    final budget = ref.watch(budgetStatusProvider);
    final marker = ref.watch(lastChangedTransactionProvider);
    final now = ref.watch(clockProvider)();
    final period = ref.watch(dashboardPeriodProvider);
    final name = settings.userName.trim();

    void openBudget() => Navigator.of(context).push(BudgetScreen.route());

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, AppShell.contentBottomInset(context)),
            sliver: SliverList.list(
              children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Chip(label: Text('${currency.code} · original amounts'), avatar: const Icon(Icons.payments_outlined, size: 18)),
                  TextButton.icon(icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    label: const Text('Wallets'), onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const WalletsScreen()))),
                ]),
                // Greeting
                Row(
                  children: [
                    Pressable(
                      onTap: () => ref.read(shellTabProvider.notifier).state = 3,
                      semanticLabel: 'Open settings',
                      child: _Avatar(name: name),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${Dates.greeting(now)}${name.isEmpty ? '' : ','}',
                            style: t.bodyMedium?.copyWith(color: p.textSecondary),
                          ),
                          Text(
                            name.isEmpty ? 'Welcome back' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width >= 390) Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 14, color: p.textSecondary),
                          const SizedBox(width: 6),
                          Text(DateFormat('EEE, MMM d').format(now),
                              style: t.labelMedium?.copyWith(color: p.textPrimary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                DropdownButtonFormField<int>(isExpanded: true,
                  initialValue: ref.watch(dashboardMonthOffsetProvider),
                  decoration: const InputDecoration(labelText: 'Income & expense period', prefixIcon: Icon(Icons.date_range_outlined)),
                  items: [for (final offset in [0, -1, -2]) DropdownMenuItem(value: offset,
                    child: Text(DateFormat('MMMM y').format(DateTime(now.year, now.month + offset))))],
                  onChanged: (value) { if(value!=null)ref.read(dashboardMonthOffsetProvider.notifier).state=value; }),
                const SizedBox(height: 16),
                if (ref.watch(transactionsProvider).hasError)
                  AppCard(child: Column(children: [const Text('Could not load transaction summaries'),
                    TextButton(onPressed: () => ref.invalidate(transactionsProvider), child: const Text('Retry'))]))
                else if (ref.watch(walletRepositoryProvider) != null && ref.watch(walletsProvider).hasError)
                  AppCard(child: Column(children: [
                    const Text('Could not load wallet balances'),
                    TextButton(onPressed: () => ref.invalidate(walletsProvider), child: const Text('Retry')),
                  ]))
                else if (ref.watch(walletRepositoryProvider) != null && ref.watch(walletsProvider).valueOrNull == null)
                  const Center(child: CircularProgressIndicator())
                else BalanceCard(
                  balanceMinor: summary.balanceMinor,
                  month: summary.month,
                  previousMonth: summary.previousMonth,
                  currency: currency,
                  hidden: settings.hideBalance,
                  onToggleHidden: () => ref.read(settingsProvider.notifier).toggleHideBalance(),
                  monthLabel: DateFormat('MMM y').format(period),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Quick actions
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        label: 'Add expense',
                        icon: Icons.north_east_rounded,
                        color: p.expense,
                        background: p.expenseSoft,
                        onTap: () => TransactionActions.openEditor(context, ref,
                            initialType: TransactionType.expense),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _QuickAction(
                        label: 'Add income',
                        icon: Icons.south_west_rounded,
                        color: p.income,
                        background: p.incomeSoft,
                        onTap: () => TransactionActions.openEditor(context, ref,
                            initialType: TransactionType.income),
                      ),
                    ),
                  ],
                ),

                AnimatedSize(
                  duration: AppDurations.medium,
                  curve: AppCurves.standard,
                  child: (budget.level == BudgetLevel.approaching ||
                          budget.level == BudgetLevel.exceeded)
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: BudgetWarningBanner(
                              status: budget, currency: currency, onTap: openBudget),
                        )
                      : const SizedBox(width: double.infinity),
                ),

                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader(title: 'Weekly spending', subtitle: 'Tap a bar for details'),
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
                const SizedBox(height: AppSpacing.xxl),
                SectionHeader(
                  title: 'Recent activity',
                  actionLabel: summary.recent.isEmpty ? null : 'See all',
                  onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(), body: const TransactionsScreen()))),
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: AnimatedSwitcher(
                    duration: AppDurations.medium,
                    child: summary.recent.isEmpty
                        ? EmptyState(
                            key: const ValueKey('empty'),
                            compact: true,
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'Start tracking',
                            message:
                                'Add your first transaction to see your balance, charts and insights come alive.',
                            actionLabel: 'Add transaction',
                            onAction: () => TransactionActions.openEditor(context, ref),
                          )
                        : Column(
                            key: const ValueKey('list'),
                            children: [
                              for (final tx in summary.recent)
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(tx.id),
                                  tween: Tween(begin: isFreshChange(marker, tx.id) ? 0 : 1, end: 1),
                                  duration: AppDurations.slow,
                                  curve: AppCurves.standard,
                                  builder: (context, v, child) => Opacity(
                                    opacity: v,
                                    child: Transform.translate(
                                        offset: Offset(0, -10 * (1 - v)), child: child),
                                  ),
                                  child: TransactionTile(
                                    transaction: tx,
                                    currency: currency,
                                    showDate: !Dates.isSameDay(tx.occurredAt, now),
                                    highlight: isFreshChange(marker, tx.id),
                                    onTap: () =>
                                        TransactionActions.openEditor(context, ref, existing: tx),
                                    onLongPress: () =>
                                        TransactionActions.showActions(context, ref, tx),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.isEmpty
        ? null
        : name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy700, AppColors.navy900],
        ),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.5), width: 1.5),
      ),
      alignment: Alignment.center,
      child: initials == null
          ? const Icon(Icons.person_outline_rounded, color: Colors.white, size: 22)
          : Text(initials,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
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
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      haptic: true,
      semanticLabel: label,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.isDark ? p.border : p.border.withValues(alpha: 0.6)),
          boxShadow: AppShadows.card(context),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
