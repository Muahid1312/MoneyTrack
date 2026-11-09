import '../../../core/constants/currency.dart';

/// Destination major units per one source major unit. Decimal text is retained
/// on the transfer; conversion uses rational integers and half-up rounding.
class ExchangeRate {
  ExchangeRate._(this.text, this.numerator, this.denominator);
  final String text;
  final BigInt numerator;
  final BigInt denominator;

  factory ExchangeRate.parse(String input) {
    final text = input.trim();
    if (!RegExp(r'^\d{1,12}(\.\d{1,12})?$').hasMatch(text)) {
      throw const FormatException('Enter a positive rate with at most 12 decimals');
    }
    final parts = text.split('.');
    final n = BigInt.parse(parts.join());
    if (n <= BigInt.zero) throw const FormatException('Rate must be positive');
    return ExchangeRate._(text, n,
        BigInt.from(10).pow(parts.length == 1 ? 0 : parts[1].length));
  }

  int convert(int minor, AppCurrency source, AppCurrency destination) {
    if (minor <= 0 || minor > AppInfo.maxAmountMinor) {
      throw ArgumentError('Invalid source amount');
    }
    final n = BigInt.from(minor) * numerator * BigInt.from(destination.scale);
    final d = denominator * BigInt.from(source.scale);
    final rounded = (n * BigInt.two + d) ~/ (d * BigInt.two);
    if (rounded <= BigInt.zero || rounded > BigInt.from(AppInfo.maxAmountMinor)) {
      throw ArgumentError('Converted amount is zero or exceeds the limit');
    }
    return rounded.toInt();
  }
}
