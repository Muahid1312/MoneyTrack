import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';

final walletRepositoryProvider = Provider<WalletRepository?>((ref) => null);

final walletsProvider = FutureProvider<WalletSnapshot?>((ref) async {
  ref.watch(transactionsProvider);
  return ref.watch(walletRepositoryProvider)?.fetch();
});

// The wallet the user is working in during this session.
final selectedWalletIdProvider = StateProvider<int?>((ref) => null);
final selectedWalletProvider = Provider<Wallet?>((ref) {
  final id = ref.watch(selectedWalletIdProvider);
  final active = ref.watch(walletsProvider).valueOrNull?.wallets.where((w) => !w.archived);
  return active?.where((w) => w.id == id).firstOrNull ?? active?.firstOrNull;
});

/// Existing reports are explicitly scoped to a single original currency.
/// No conversion rate is inferred from the display/reporting preference.
final reportingTransactionsProvider = Provider<List<TransactionModel>>((ref) {
  final currency = ref.watch(currencyProvider);
  return ref.watch(allTransactionsProvider)
      .where((t) => t.currency == currency).toList(growable: false);
});

final currencyBalancesProvider = Provider<Map<AppCurrency, int>>((ref) {
  final snapshot = ref.watch(walletsProvider).valueOrNull;
  if (snapshot == null) {
    final out = <AppCurrency, int>{};
    for (final t in ref.watch(allTransactionsProvider)) {
      out[t.currency] = (out[t.currency] ?? 0) + t.signedMinor;
    }
    return out;
  }
  final out = <AppCurrency, int>{};
  for (final w in snapshot.wallets) {
    out[w.currency] = (out[w.currency] ?? 0) + snapshot.balances[w.id]!;
  }
  return out;
});
