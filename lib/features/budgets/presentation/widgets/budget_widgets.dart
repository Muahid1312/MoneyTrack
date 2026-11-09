import 'package:flutter/material.dart';

import '../../../../core/constants/currency.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/animated_money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/progress.dart';
import '../../domain/budget_calculator.dart';

String budgetLevelLabel(BudgetLevel l) => switch (l) {
      BudgetLevel.notSet => 'Not set',
      BudgetLevel.healthy => 'On track',
      BudgetLevel.approaching => 'Almost at limit',
      BudgetLevel.exceeded => 'Over budget',
    };

class BudgetLevelChip extends StatelessWidget {
  const BudgetLevelChip({super.key, required this.level});
  final BudgetLevel level;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color fg, Color bg, IconData icon) = switch (level) {
      BudgetLevel.exceeded => (p.expense, p.expenseSoft, Icons.error_outline_rounded),
      BudgetLevel.approaching => (p.warning, p.warningSoft, Icons.warning_amber_rounded),
      _ => (p.income, p.incomeSoft, Icons.check_circle_outline_rounded),
    };
    return AnimatedContainer(
      duration: AppDurations.medium,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(budgetLevelLabel(level),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Inline warning banner shown when approaching/over budget.
class BudgetWarningBanner extends StatelessWidget {
  const BudgetWarningBanner({super.key, required this.status, required this.currency, this.onTap});
  final BudgetStatus status;
  final AppCurrency currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final over = status.level == BudgetLevel.exceeded;
    final fg = over ? p.expense : p.warning;
    final bg = over ? p.expenseSoft : p.warningSoft;
    final title = over ? "You're over budget" : "You're close to your budget";
    final body = over
        ? 'Spending is ${Money.format(status.overspentMinor, currency)} above this month\'s limit.'
        : '${(status.ratio * 100).floor()}% used · ${Money.format(status.remainingMinor, currency)} left for ${status.daysLeft} ${status.daysLeft == 1 ? 'day' : 'days'}.';
    return AppCard(
      onTap: onTap,
      color: bg,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(over ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                color: fg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: t.bodySmall?.copyWith(color: p.textPrimary.withValues(alpha: 0.8))),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: fg),
        ],
      ),
    );
  }
}

/// Dashboard budget overview.
class BudgetSummaryCard extends StatelessWidget {
  const BudgetSummaryCard({
    super.key,
    required this.status,
    required this.currency,
    required this.onOpen,
    required this.onSetBudget,
  });

  final BudgetStatus status;
  final AppCurrency currency;
  final VoidCallback onOpen;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    if (!status.hasBudget) {
      return AppCard(
        onTap: onSetBudget,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: context.isDark ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.track_changes_rounded,
                  color: context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set a monthly budget', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Get warned before you overspend.',
                      style: t.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          ],
        ),
      );
    }

    final color = budgetColor(context, status.ratio);
    final over = status.remainingMinor < 0;
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Monthly budget',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              BudgetLevelChip(level: status.level),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: AnimatedMoney(
                  minor: status.spentMinor,
                  currency: currency,
                  style: AppTypography.amount(22, weight: FontWeight.w800, color: p.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text('of ${Money.format(status.budgetMinor, currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(color: p.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedProgressBar(value: status.ratio, color: color, height: 10),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  over
                      ? 'Over by ${Money.format(status.overspentMinor, currency)}'
                      : '${Money.format(status.remainingMinor, currency)} left',
                  style: t.labelLarge?.copyWith(color: over ? p.expense : p.textPrimary),
                ),
              ),
              Text(
                over
                    ? '${status.daysLeft}d left'
                    : '${Money.format(status.dailyAllowanceMinor, currency)}/day · ${status.daysLeft}d',
                style: t.labelMedium?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BudgetEmptyCta extends StatelessWidget {
  const BudgetEmptyCta({super.key, required this.onSet});
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) => PrimaryButton(
        label: 'Set monthly budget',
        icon: Icons.track_changes_rounded,
        onPressed: onSet,
      );
}
