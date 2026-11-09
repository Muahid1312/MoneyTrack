import 'package:flutter/material.dart';

import '../../core/constants/currency.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.currency = AppCurrency.usd,
    this.monthlyBudgetMinor = 0,
    this.userName = '',
    this.hideBalance = false,
  });

  final ThemeMode themeMode;
  final AppCurrency currency;

  /// 0 means "no budget set".
  final int monthlyBudgetMinor;
  final String userName;
  final bool hideBalance;

  bool get hasBudget => monthlyBudgetMinor > 0;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppCurrency? currency,
    int? monthlyBudgetMinor,
    String? userName,
    bool? hideBalance,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        currency: currency ?? this.currency,
        monthlyBudgetMinor: monthlyBudgetMinor ?? this.monthlyBudgetMinor,
        userName: userName ?? this.userName,
        hideBalance: hideBalance ?? this.hideBalance,
      );
}
