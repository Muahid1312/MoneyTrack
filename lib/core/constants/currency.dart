enum AppCurrency {
  afn(code: 'AFN', symbol: '؋', name: 'Afghan Afghani', symbolAfter: true),
  usd(code: 'USD', symbol: r'$', name: 'US Dollar'),
  eur(code: 'EUR', symbol: '€', name: 'Euro'),
  pkr(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee', symbolAfter: true),
  jpy(code: 'JPY', symbol: '¥', name: 'Japanese Yen', decimalDigits: 0),
  kwd(code: 'KWD', symbol: 'KD', name: 'Kuwaiti Dinar', decimalDigits: 3);

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    this.symbolAfter = false,
    this.decimalDigits = 2,
  });

  final String code;
  final String symbol;
  final String name;
  final bool symbolAfter;
  final int decimalDigits;
  int get scale {
    var result = 1;
    for (var i = 0; i < decimalDigits; i++) { result *= 10; }
    return result;
  }

  static AppCurrency requireCode(String code) => values.firstWhere(
    (c) => c.code == code, orElse: () => throw ArgumentError("Unsupported currency: $code"));

  static AppCurrency fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => AppCurrency.usd);
}

abstract final class AppInfo {
  static const name = 'MoneyTrack';
  static const version = '2.0.0';
  static const tagline = 'Calm, private money tracking.';

  /// Largest accepted amount in minor units, independently of currency precision.
  static const maxAmountMinor = 99999999999;

  /// Budget usage ratio at which the "approaching" warning appears.
  static const budgetWarningRatio = 0.8;
}
