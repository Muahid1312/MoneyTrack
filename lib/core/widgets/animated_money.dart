import 'package:flutter/material.dart';

import '../constants/currency.dart';
import '../theme/app_tokens.dart';
import '../utils/money.dart';

/// Counts smoothly between values when an amount changes. The tween runs on
/// a double purely for display; each frame is rounded back to whole minor
/// units before formatting.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney({
    super.key,
    required this.minor,
    required this.currency,
    required this.style,
    this.signed = false,
    this.obscured = false,
    this.duration = const Duration(milliseconds: 700),
    this.textAlign,
  });

  final int minor;
  final AppCurrency currency;
  final TextStyle? style;
  final bool signed;
  final bool obscured;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (obscured) {
      return Text(
        currency.symbolAfter ? '•••••• ${currency.symbol}' : '${currency.symbol}••••••',
        style: style,
        textAlign: textAlign,
        semanticsLabel: 'Hidden amount',
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: minor.toDouble()),
      duration: duration,
      curve: AppCurves.emphasized,
      builder: (context, value, _) => Text(
        Money.format(value.round(), currency, signed: signed),
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: Money.format(minor, currency, signed: signed),
      ),
    );
  }
}
