import '../../../core/utils/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/progress.dart';
import '../../planning/application/planning_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../application/budget_providers.dart';
import 'budget_editor_sheet.dart';
import 'budget_screen.dart';
import 'wallet_budget_panel.dart';

class BudgetsOverviewScreen extends ConsumerWidget {
  const BudgetsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(budgetStatusProvider);
    final wallet = ref.watch(selectedWalletProvider);
    final month = MaterialLocalizations.of(
      context,
    ).formatMonthYear(status.month.start);
    final ratio = status.ratio;
    final color = budgetColor(context, ratio);
    final t = Theme.of(context).textTheme;
    String money(int minor) =>
        settings.hideBalance ? '••••' : Money.format(minor, settings.currency);
    final canAddWalletBudget =
        wallet != null && ref.watch(planningRepositoryProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Budgets', 'بودجه‌ها'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(month, style: t.titleMedium)),
              FilledButton.icon(
                onPressed: () => canAddWalletBudget
                    ? showWalletBudgetEditor(context, wallet)
                    : showBudgetEditor(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('Add budget', 'افزودن بودجه')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${context.tr('Monthly spending limit', 'حد مصرف ماهانه')} · ${settings.currency.code}',
                  style: t.labelLarge,
                ),
                const SizedBox(height: 12),
                if (ref.watch(transactionsProvider).isLoading)
                  const LinearProgressIndicator()
                else if (ref.watch(transactionsProvider).hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(transactionsProvider),
                    child: const Text('Retry loading spending'),
                  )
                else if (!status.hasBudget)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(status.spentMinor),
                        style: AppTypography.amount(29),
                      ),
                      Text(context.tr('Spent this month', 'مصرف این ماه')),
                      TextButton(
                        onPressed: () => showBudgetEditor(context),
                        child: Text(
                          context.tr(
                            'Set monthly budget',
                            'تعیین بودجهٔ ماهانه',
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Row(
                    children: [
                      ProgressRing(
                        value: settings.hideBalance ? 0 : ratio,
                        color: color,
                        size: 74,
                        stroke: 8,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: FittedBox(
                            child: Text(
                              settings.hideBalance
                                  ? '••••'
                                  : '${(ratio * 100).round()}%',
                              style: t.labelLarge?.copyWith(color: color),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              money(status.spentMinor),
                              style: AppTypography.amount(25),
                            ),
                            Text(
                              'of ${money(status.budgetMinor)}',
                              style: t.bodySmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              status.remainingMinor < 0
                                  ? '${money(-status.remainingMinor)} over budget'
                                  : '${money(status.remainingMinor)} remaining',
                              style: t.labelMedium?.copyWith(
                                color: status.remainingMinor < 0
                                    ? context.palette.expense
                                    : context.accent.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AnimatedProgressBar(
                    value: settings.hideBalance ? 0 : ratio,
                    color: color,
                    height: 7,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.push(context, BudgetScreen.route()),
                      child: Text(
                        context.tr('Monthly details', 'جزئیات ماهانه'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(title: context.tr('Wallet budgets', 'بودجه‌های حساب')),
          const SizedBox(height: 6),
          const WalletBudgetPanel(showPosition: false),
        ],
      ),
    );
  }
}
