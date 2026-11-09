import '../constants/currency.dart';
import 'money.dart';

/// Immutable keypad buffer for amount entry. Keeps the raw string the user
/// typed (so "12." and "12.50" render as typed) and converts to exact
/// integer minor units.
class AmountInput {
  const AmountInput([this.raw = '', this.currency = AppCurrency.usd]);
  final AppCurrency currency;

  factory AmountInput.fromMinor(int minor, [AppCurrency currency = AppCurrency.usd]) {
    if (minor <= 0) return AmountInput('', currency);
    var text = Money.plain(minor, currency);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return AmountInput(text, currency);
  }

  final String raw;

  static const maxIntegerDigits = 9;

  bool get isEmpty => raw.isEmpty;
  bool get hasDecimal => raw.contains('.');

  AmountInput appendDigit(int digit) {
    assert(digit >= 0 && digit <= 9);
    if (hasDecimal) {
      final decimals = raw.length - raw.indexOf('.') - 1;
      if (decimals >= currency.decimalDigits) return this;
      return _next('$raw$digit');
    }
    if (raw == '0') return digit == 0 ? this : _next('$digit');
    if (raw.length >= maxIntegerDigits) return this;
    return _next('$raw$digit');
  }

  AmountInput _next(String text) => Money.parseMinor(text, currency) == null
      ? this : AmountInput(text, currency);

  AmountInput appendDecimal() {
    if (hasDecimal || currency.decimalDigits == 0) return this;
    return AmountInput(raw.isEmpty ? '0.' : '$raw.', currency);
  }

  AmountInput backspace() =>
      raw.isEmpty ? this : AmountInput(raw.substring(0, raw.length - 1), currency);

  AmountInput clear() => AmountInput('', currency);

  /// Exact value in minor units (cents).
  int get minor => raw.isEmpty ? 0 : Money.parseMinor(raw, currency) ?? 0;

  /// Grouped display of what was typed: "1,234.5".
  String get display {
    if (raw.isEmpty) return '0';
    final parts = raw.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    if (parts.length > 1) buf.write('.${parts[1]}');
    return buf.toString();
  }
}
