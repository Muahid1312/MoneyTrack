import '../storage/access_guard.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/currency.dart';
import '../../core/theme/app_accent.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kTheme = 'theme_mode';
  static const languageKey = 'appearance_language';
  static const _kCurrency = 'currency';
  static const _kBudget = 'monthly_budget_minor';
  static const _kName = 'user_name';
  static const _kHideBalance = 'hide_balance';

  AppSettings load() => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == _prefs.getString(_kTheme),
          orElse: () => ThemeMode.system,
        ),
        language: AppLanguageChoice.values.firstWhere(
          (choice) => choice.name == _prefs.getString(languageKey),
          orElse: () => AppLanguageChoice.english,
        ),
        currency: AppCurrency.fromCode(_prefs.getString(_kCurrency)),
        monthlyBudgetMinor: (_prefs.getInt(_kBudget) ?? 0).clamp(0, 1 << 52),
        userName: _prefs.getString(_kName) ?? '',
        hideBalance: _prefs.getBool(_kHideBalance) ?? false,
      );

  AccentPreference loadAccent() => AccentPreference.decode(
    _prefs.getString(AppAccent.preferenceKey) ?? '',
  ) ?? const AccentPreference();

  Future<void> saveAccent(AccentPreference preference) async {
    AccessGuard.writable();
    if (!await _prefs.setString(AppAccent.preferenceKey, preference.encode())) {
      throw StateError('Appearance could not be saved.');
    }
  }

  Future<void> clearBudgets() async {
    AccessGuard.writable();
    for (final c in AppCurrency.values) {
      await _prefs.remove('budget_${c.code}');
    }
  }

  int budgetFor(AppCurrency currency) =>
      _prefs.getInt('budget_${currency.code}') ?? 0;

  Future<void> save(AppSettings s) async {
    AccessGuard.writable();
    await Future.wait([
      _prefs.setString(_kTheme, s.themeMode.name),
      _prefs.setString(languageKey, s.language.name),
      _prefs.setString(_kCurrency, s.currency.code),
      _prefs.setInt(_kBudget, s.monthlyBudgetMinor),
      _prefs.setInt('budget_${s.currency.code}', s.monthlyBudgetMinor),
      _prefs.setString(_kName, s.userName),
      _prefs.setBool(_kHideBalance, s.hideBalance),
    ]);
  }
}
