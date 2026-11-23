import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../data/storage/app_runtime.dart';
import '../domain/group_fund.dart';

final groupRepositoryProvider = Provider<GroupRepository?>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  return runtime == null ? null : GroupRepository(runtime.database);
});
final groupsProvider = FutureProvider.autoDispose<List<DataRow>>(
  (ref) async => await ref.watch(groupRepositoryProvider)?.list() ?? [],
);
final groupProvider = FutureProvider.autoDispose.family<GroupFund, int>(
  (ref, id) => ref.watch(groupRepositoryProvider)!.get(id),
);
