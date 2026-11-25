import 'package:flutter/material.dart';

import '../../core/constants/currency.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguageChoice.english,
    this.currency = AppCurrency.usd,
    this.monthlyBudgetMinor = 0,
    this.userName = '',
    this.hideBalance = false,
  });

  final ThemeMode themeMode;
  final AppLanguageChoice language;
  final AppCurrency currency;

  /// 0 means "no budget set".
  final int monthlyBudgetMinor;
  final String userName;
  final bool hideBalance;

  bool get hasBudget => monthlyBudgetMinor > 0;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguageChoice? language,
    AppCurrency? currency,
    int? monthlyBudgetMinor,
    String? userName,
    bool? hideBalance,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        currency: currency ?? this.currency,
        monthlyBudgetMinor: monthlyBudgetMinor ?? this.monthlyBudgetMinor,
        userName: userName ?? this.userName,
        hideBalance: hideBalance ?? this.hideBalance,
      );
}

enum AppLanguageChoice {
  english(Locale('en')), dari(Locale('fa', 'AF'));
  const AppLanguageChoice(this.locale);
  final Locale locale;
}
