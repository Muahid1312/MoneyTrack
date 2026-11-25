import 'package:flutter/material.dart';

import '../../../../core/constants/currency.dart';
import '../../../../core/theme/app_accent.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/finance_hero.dart';
import '../../../statistics/domain/finance_calculator.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balanceMinor,
    required this.month,
    required this.previousMonth,
    required this.currency,
    required this.hidden,
    required this.onToggleHidden,
    required this.monthLabel,
  });

  final int balanceMinor;
  final Totals month, previousMonth;
  final AppCurrency currency;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    String money(int amount) =>
        hidden ? '••••' : Money.format(amount, currency);
    final change = FinanceCalculator.percentChange(
      previousMonth.expense,
      month.expense,
    );
    return FinanceHero(
      label: 'Wallet cash · ${currency.code}',
      amount: money(balanceMinor),
      action: IconButton(
        tooltip: hidden ? 'Show balance' : 'Hide balance',
        onPressed: onToggleHidden,
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: context.accent.cardInk,
        ),
      ),
      details: [
        (label: 'Income · $monthLabel', value: money(month.income)),
        (label: 'Expenses · $monthLabel', value: money(month.expense)),
        (label: 'Cash flow', value: money(month.net)),
        if (change != null)
          (
            label: 'Spending vs prior month',
            value: hidden
                ? '••••'
                : '${change > 0 ? '+' : ''}${change.toStringAsFixed(0)}%',
          ),
      ],
    );
  }
}
