import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/project_repository.dart';
import '../../transactions/application/transactions_controller.dart';

final projectRepositoryProvider = Provider<ProjectRepository?>((ref) => null);

final projectsProvider = FutureProvider<ProjectSnapshot?>((ref) async {
  ref.watch(transactionsProvider);
  return ref.watch(projectRepositoryProvider)?.fetch();
});
