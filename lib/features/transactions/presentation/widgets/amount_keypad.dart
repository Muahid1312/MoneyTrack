import 'package:flutter/material.dart';

import '../../../../core/theme/app_accent.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';

sealed class KeypadKey {
  const KeypadKey();
}

class DigitKey extends KeypadKey {
  const DigitKey(this.digit);
  final int digit;
}

class DecimalKey extends KeypadKey {
  const DecimalKey();
}

class BackspaceKey extends KeypadKey {
  const BackspaceKey();
}

class ClearKey extends KeypadKey {
  const ClearKey();
}

/// Large-target numeric keypad. Long-press backspace clears the amount.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, this.keyHeight = 50, this.allowDecimal = true, this.enabled = true});

  final ValueChanged<KeypadKey> onKey;
  final double keyHeight;
  final bool allowDecimal, enabled;

  @override
  Widget build(BuildContext context) {
    const rows = [
      [DigitKey(1), DigitKey(2), DigitKey(3)],
      [DigitKey(4), DigitKey(5), DigitKey(6)],
      [DigitKey(7), DigitKey(8), DigitKey(9)],
      [DecimalKey(), DigitKey(0), BackspaceKey()],
    ];
    return Column(
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final k in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _Key(
                      keyValue: k,
                      height: keyHeight,
                      onTap: enabled && (allowDecimal || k is! DecimalKey) ? () => onKey(k) : null,
                      onLongPress: enabled && k is BackspaceKey ? () => onKey(const ClearKey()) : null,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.keyValue,
    required this.height,
    required this.onTap,
    this.onLongPress,
  });

  final KeypadKey keyValue;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = context.accent;
    final k = widget.keyValue;
    final (Widget child, String label) = switch (k) {
      DigitKey(:final digit) => (
          Text('$digit',
              style: AppTypography.amount(26, weight: FontWeight.w600, color: p.textPrimary)),
          '$digit'
        ),
      DecimalKey() => (
          Text('.',
              style: AppTypography.amount(30, weight: FontWeight.w700, color: a.onSurface)),
          'Decimal point'
        ),
      BackspaceKey() => (
          Icon(Icons.backspace_outlined, size: 22, color: a.onSurface),
          'Delete digit. Long press to clear'
        ),
      ClearKey() => (const SizedBox.shrink(), 'Clear'),
    };
    return Semantics(
      button: true,
      label: label,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                setState(() => _down = false);
                widget.onLongPress!();
              },
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOut,
          height: widget.height,
          decoration: BoxDecoration(
            color: _down
                ? a.surface
                : k is DigitKey ? p.surface : a.surface,
            borderRadius: AppRadii.control,
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: AppDurations.fast,
            child: child,
          ),
        ),
      ),
    );
  }
}

AmountInput applyAmountKey(AmountInput input, KeypadKey key) => switch (key) {
  DigitKey(:final digit) => input.appendDigit(digit),
  DecimalKey() => input.appendDecimal(),
  BackspaceKey() => input.backspace(),
  ClearKey() => input.clear(),
};
