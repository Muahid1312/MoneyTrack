import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/amount_input.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../wallets/application/wallet_providers.dart';

/// Opens the monthly budget editor. Persists on save.
Future<void> showBudgetEditor(BuildContext context) {
  return showAppSheet<void>(context, builder: (_) => const _BudgetEditor());
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor();

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(settingsProvider).monthlyBudgetMinor;
    _controller = TextEditingController(
        text: current > 0 ? AmountInput.fromMinor(current, ref.read(currencyProvider)).raw : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save([int? override]) async {
    final minor = override ?? Money.parseMinor(_controller.text, ref.read(currencyProvider));
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid amount greater than zero');
      HapticFeedback.heavyImpact();
      return;
    }
    if (minor > AppInfo.maxAmountMinor) {
      setState(() => _error = 'That amount is too large');
      return;
    }
    await ref.read(settingsProvider.notifier).setMonthlyBudget(minor);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    showAppSnack(context, message: 'Monthly budget set to ${Money.format(minor, ref.read(currencyProvider))}');
  }

  Future<void> _remove() async {
    await ref.read(settingsProvider.notifier).setMonthlyBudget(0);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final currency = ref.watch(currencyProvider);
    final hasBudget = ref.watch(settingsProvider).hasBudget;
    final now = ref.read(clockProvider)();
    final txs = ref.watch(reportingTransactionsProvider);
    final lastMonth = FinanceCalculator.totals(txs,
            span: DateSpan.month(DateTime(now.year, now.month - 1)))
        .expense;
    // Suggest last month's spending rounded up to a tidy figure.
    int? suggestion;
    if (lastMonth > 0) {
      final step = 50 * currency.scale; // 50.00 in minor units
      suggestion = ((lastMonth + step - 1) ~/ step) * step;
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            title: 'Monthly budget',
            subtitle: 'A spending limit for each calendar month.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
              ],
              style: AppTypography.amount(28, weight: FontWeight.w800, color: p.textPrimary),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _error,
                prefixIcon: currency.symbolAfter
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 18, right: 6),
                        child: Text(currency.symbol,
                            style: AppTypography.amount(24,
                                weight: FontWeight.w600, color: p.textSecondary)),
                      ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: currency.symbolAfter
                    ? Padding(
                        padding: const EdgeInsets.only(right: 18, left: 6),
                        child: Text(currency.symbol,
                            style: AppTypography.amount(24,
                                weight: FontWeight.w600, color: p.textSecondary)),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              ),
            ),
          ),
          if (suggestion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  onTap: () {
                    _controller.text = AmountInput.fromMinor(suggestion!, currency).raw;
                    setState(() => _error = null);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: context.isDark ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_outlined,
                            size: 16, color: context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Use ${Money.format(suggestion, currency)} · based on last month',
                            style: t.labelMedium?.copyWith(
                                color: context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                if (hasBudget) ...[
                  Expanded(
                    child: SecondaryButton(
                      label: 'Remove',
                      color: p.expense,
                      onPressed: _remove,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: PrimaryButton(label: 'Save budget', height: 52, onPressed: _save),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
