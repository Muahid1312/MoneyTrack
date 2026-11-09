import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/progress.dart';
import '../../settings/application/settings_controller.dart';
import '../application/budget_providers.dart';
import '../domain/budget_calculator.dart';
import 'budget_editor_sheet.dart';
import 'widgets/budget_widgets.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const BudgetScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final status = ref.watch(budgetStatusProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: AppIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              size: 40,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        leadingWidth: 64,
        title: const Text('Budget'),
        actions: [
          if (status.hasBudget)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit budget',
                size: 40,
                onPressed: () => showBudgetEditor(context),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !status.hasBudget
            ? Center(
                child: EmptyState(
                  icon: Icons.track_changes_rounded,
                  title: 'No budget yet',
                  message:
                      'Set a monthly spending limit to track how much you have left and get warned at 80% and 100%.',
                  actionLabel: 'Set monthly budget',
                  onAction: () => showBudgetEditor(context),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 8, AppSpacing.screen, 32),
                children: [
                  Text(DateFormat('MMMM y').format(status.month.start),
                      style: t.labelLarge?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpacing.lg),
                  _RingCard(status: status, currency: currency),
                  if (status.level == BudgetLevel.approaching ||
                      status.level == BudgetLevel.exceeded) ...[
                    const SizedBox(height: AppSpacing.lg),
                    BudgetWarningBanner(status: status, currency: currency),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _StatsGrid(status: status, currency: currency),
                  const SizedBox(height: AppSpacing.xxl),
                  SectionHeader(
                    title: 'Spending by category',
                    subtitle: 'Share of this month\'s budget',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (status.categories.isEmpty)
                    const AppCard(
                      child: EmptyState(
                        compact: true,
                        icon: Icons.pie_chart_outline_rounded,
                        title: 'No spending yet',
                        message: 'Expenses you add this month will be broken down here.',
                      ),
                    )
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Column(
                        children: [
                          for (final c in status.categories)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  CategoryAvatar(category: c.category, size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(c.category.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: t.titleSmall),
                                            ),
                                            Text(Money.format(c.amountMinor, currency),
                                                style: AppTypography.amount(14,
                                                    color: p.textPrimary)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: AnimatedProgressBar(
                                                value: c.amountMinor / status.budgetMinor,
                                                color: c.category.color,
                                                height: 6,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            SizedBox(
                                              width: 40,
                                              child: Text(
                                                '${(c.amountMinor / status.budgetMinor * 100).toStringAsFixed(0)}%',
                                                textAlign: TextAlign.right,
                                                style: t.labelSmall
                                                    ?.copyWith(color: p.textSecondary),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({required this.status, required this.currency});
  final BudgetStatus status;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final color = budgetColor(context, status.ratio);
    final over = status.remainingMinor < 0;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          ProgressRing(
            value: status.ratio,
            color: color,
            size: 196,
            stroke: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(over ? 'Over by' : 'Remaining',
                    style: t.labelMedium?.copyWith(color: p.textSecondary)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedMoney(
                      minor: over ? status.overspentMinor : status.remainingMinor,
                      currency: currency,
                      style: AppTypography.amount(26,
                          weight: FontWeight.w800, color: over ? p.expense : p.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${(status.ratio * 100).toStringAsFixed(0)}% used',
                    style: t.labelMedium?.copyWith(color: color)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BudgetLevelChip(level: status.level),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.status, required this.currency});
  final BudgetStatus status;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final projectedOver = status.projectedMinor > status.budgetMinor;
    final items = [
      ('Budget', Money.format(status.budgetMinor, currency), Icons.flag_outlined, p.textPrimary),
      ('Spent', Money.format(status.spentMinor, currency), Icons.north_east_rounded, p.expense),
      (
        'Daily allowance',
        Money.format(status.dailyAllowanceMinor, currency),
        Icons.today_outlined,
        context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep
      ),
      (
        'Projected',
        Money.format(status.projectedMinor, currency),
        Icons.insights_outlined,
        projectedOver ? p.warning : p.textPrimary
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (label, value, icon, color) in items)
            SizedBox(
              width: w,
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: p.textSecondary),
                    const SizedBox(height: 10),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: AppTypography.amount(17, color: color)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}
