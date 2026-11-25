import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/managed_fund_repository.dart';
import '../../../data/storage/app_runtime.dart';
import '../domain/managed_fund.dart';

final managedFundRepositoryProvider = Provider<ManagedFundRepository?>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  return runtime == null ? null : ManagedFundRepository(runtime.database);
});

final managedFundsProvider = FutureProvider.autoDispose<List<ManagedFund>>(
  (ref) async => await ref.watch(managedFundRepositoryProvider)?.list() ?? [],
);

final managedFundProvider = FutureProvider.autoDispose
    .family<ManagedFundDetail, int>(
      (ref, id) => ref.watch(managedFundRepositoryProvider)!.get(id),
    );
