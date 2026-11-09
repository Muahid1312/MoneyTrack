import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_repository.dart';
import 'transaction_repository.dart';

/// Overridden in main.dart once the database and preferences are open.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => throw UnimplementedError('transactionRepositoryProvider'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider'),
);

/// Injectable clock so calculations are testable.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
