import 'package:flutter/material.dart';
import '../../../core/widgets/ledger_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/progress.dart';
import '../../settings/application/settings_controller.dart';
import '../application/budget_providers.dart';
import '../domain/budget_calculator.dart';
import 'budget_editor_sheet.dart';
import 'wallet_budget_panel.dart';
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
        titleSpacing: 0,
        title: const Text('Monthly spending limit'),
        actions: [
          IconButton(tooltip: 'Wallet budgets', icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
              Scaffold(appBar: AppBar(title: const Text('Wallet budgets')), body: ListView(children: const [WalletBudgetPanel()]))))),
          if (status.hasBudget)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit budget',
              onPressed: () => showBudgetEditor(context),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !status.hasBudget
            ? Center(
                child: EmptyState(
                  icon: Icons.track_changes_rounded,
                  title: 'No monthly limit yet',
                  message:
                      'Set a limit across all ${currency.code} wallets. You’ll get an alert at 80% and 100%.',
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
                  _BudgetSummary(status: status, currency: currency),
                  if (status.level == BudgetLevel.approaching ||
                      status.level == BudgetLevel.exceeded) ...[
                    const SizedBox(height: AppSpacing.lg),
                    BudgetWarningBanner(status: status, currency: currency),
                  ],
                  const SizedBox(height: AppSpacing.lg),
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

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.status,required this.currency});
  final BudgetStatus status;final AppCurrency currency;
  @override Widget build(BuildContext context){
    final over=status.remainingMinor<0;
    String money(int minor)=>Money.format(minor,currency);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      FinancialSummary([(label:'Limit',value:money(status.budgetMinor),color:null),(label:'Spent',value:money(status.spentMinor),color:context.palette.expense),(label:over?'Over by':'Remaining',value:money(over?status.overspentMinor:status.remainingMinor),color:over?context.palette.expense:null)]),
      const SizedBox(height:12),AnimatedProgressBar(value:status.ratio.clamp(0.0,1.0),color:budgetColor(context,status.ratio),height:5),
      Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Wrap(spacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[Text('${(status.ratio*100).toStringAsFixed(0)}% used'),BudgetLevelChip(level:status.level)])),
      FinancialSummary([(label:'Daily allowance',value:money(status.dailyAllowanceMinor),color:null),(label:'Projected',value:money(status.projectedMinor),color:null)])
    ]);
  }
}
