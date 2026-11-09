import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/repositories/providers.dart';

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final currencyProvider =
    Provider<AppCurrency>((ref) => ref.watch(settingsProvider).currency);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> _update(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).save(next);
    state = next;
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  Future<void> setCurrency(AppCurrency c) async {
    if (c == state.currency) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.save(state);
    await _update(state.copyWith(currency: c, monthlyBudgetMinor: repo.budgetFor(c)));
  }

  Future<void> setMonthlyBudget(int minor) =>
      _update(state.copyWith(monthlyBudgetMinor: minor < 0 ? 0 : minor));

  Future<void> setUserName(String name) =>
      _update(state.copyWith(userName: name.trim()));

  Future<void> toggleHideBalance() =>
      _update(state.copyWith(hideBalance: !state.hideBalance));

  /// Restores defaults (used by "Clear all data").
  Future<void> reset() async {
    await ref.read(settingsRepositoryProvider).clearBudgets();
    await _update(const AppSettings());
  }
}
