import 'package:intl/intl.dart';

import '../constants/currency.dart';

abstract final class Money {
  static final _grouped = NumberFormat('#,##0', 'en_US');

  static String format(int minor, AppCurrency currency,
      {bool signed = false, bool showDecimals = true}) {
    final value = minor.abs();
    final scale = currency.scale;
    final major = value ~/ scale;
    final fraction = value % scale;
    final number = showDecimals && currency.decimalDigits > 0
        ? '${_grouped.format(major)}.${fraction.toString().padLeft(currency.decimalDigits, '0')}'
        : _grouped.format(showDecimals ? major : (value * 2 + scale) ~/ (scale * 2));
    final body = _attach(number, currency);
    return minor < 0 ? '−$body' : signed && minor > 0 ? '+$body' : body;
  }

  static String compact(int minor, AppCurrency currency) {
    final value = minor.abs();
    final scale = currency.scale;
    var divisor = 1;
    var suffix = '';
    for (final entry in [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')]) {
      if (value >= entry.$1 * scale) {
        divisor = entry.$1;
        suffix = entry.$2;
        break;
      }
    }
    final d = scale * divisor;
    String body;
    if (suffix.isEmpty || value >= 100 * d) {
      body = '${(value * 2 + d) ~/ (2 * d)}$suffix';
    } else {
      final tenths = (value * 20 + d) ~/ (2 * d);
      body = '${tenths ~/ 10}${tenths % 10 == 0 ? '' : '.${tenths % 10}'}$suffix';
    }
    return '${minor < 0 ? '−' : ''}${_attach(body, currency)}';
  }

  static String plain(int minor, [AppCurrency currency = AppCurrency.usd]) {
    final value = minor.abs();
    final fraction = currency.decimalDigits == 0 ? ''
        : '.${(value % currency.scale).toString().padLeft(currency.decimalDigits, '0')}';
    return '${minor < 0 ? '-' : ''}${value ~/ currency.scale}$fraction';
  }

  /// Strict fixed-point parser. Separators must form valid three-digit groups.
  static int? parseMinor(String input, [AppCurrency currency = AppCurrency.usd]) {
    final text = input.trim();
    final digits = currency.decimalDigits;
    final pattern = digits == 0
        ? r'^(\d+|\d{1,3}(,\d{3})+)$'
        : '^(\\d+|\\d{1,3}(,\\d{3})+)(\\.\\d{0,$digits})?\$';
    if (!RegExp(pattern).hasMatch(text)) return null;
    final parts = text.replaceAll(',', '').split('.');
    final major = BigInt.tryParse(parts[0]);
    if (major == null) return null;
    final fraction = parts.length == 1 || parts[1].isEmpty
        ? BigInt.zero : BigInt.parse(parts[1].padRight(digits, '0'));
    final value = major * BigInt.from(currency.scale) + fraction;
    if (value > BigInt.from(AppInfo.maxAmountMinor)) return null;
    return value.toInt();
  }

  static String _attach(String number, AppCurrency c) =>
      c.symbolAfter ? '$number ${c.symbol}' : '${c.symbol}$number';
}
