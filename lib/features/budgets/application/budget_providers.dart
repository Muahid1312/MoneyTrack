import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../domain/budget_calculator.dart';

final budgetStatusProvider = Provider<BudgetStatus>((ref) {
  final budget =
      ref.watch(settingsProvider.select((s) => s.monthlyBudgetMinor));
  final txs = ref.watch(reportingTransactionsProvider);
  final now = ref.watch(clockProvider)();
  return BudgetCalculator.compute(
      budgetMinor: budget, transactions: txs, now: now);
});
