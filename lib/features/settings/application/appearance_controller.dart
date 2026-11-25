import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_accent.dart';
import '../../../data/repositories/providers.dart';

final accentProvider = NotifierProvider<AccentController, AccentPreference>(
  AccentController.new,
);

class AccentController extends Notifier<AccentPreference> {
  @override
  AccentPreference build() =>
      ref.watch(settingsRepositoryProvider).loadAccent();

  Future<void> select(Color seed) => _save(state.select(seed));

  Future<void> reset() => _save(const AccentPreference());

  Future<void> _save(AccentPreference next) async {
    await ref.read(settingsRepositoryProvider).saveAccent(next);
    state = next;
  }
}
