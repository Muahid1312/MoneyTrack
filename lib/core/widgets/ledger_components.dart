import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

typedef LedgerFigure = ({String label, String value, Color? color});

/// Shows exact amounts in columns. Switches to rows when amounts or system text grow.
class FinancialSummary extends StatelessWidget {
  const FinancialSummary(this.figures, {super.key});
  final List<LedgerFigure> figures;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final base = AppTypography.amount(15);
    return Material(
      color: p.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: p.border, width: .7),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth / figures.length - 20;
            bool fits(String text, TextStyle style) {
              final measure = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final ok = measure.width <= width;
              measure.dispose();
              return ok;
            }

            final stacked = figures.any(
              (f) => !fits(f.value, base) || !fits(f.label, theme.labelMedium!),
            );
            Widget label(LedgerFigure f) => Text(
              f.label,
              style: theme.labelMedium?.copyWith(color: p.textSecondary),
            );
            Widget value(LedgerFigure f) => Text(
              f.value,
              textAlign: stacked ? TextAlign.end : TextAlign.start,
              style: base.copyWith(color: f.color ?? p.textPrimary),
            );
            if (stacked) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    for (final f in figures)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: OverflowBar(
                          alignment: MainAxisAlignment.spaceBetween,
                          overflowAlignment: OverflowBarAlignment.end,
                          spacing: 8,
                          children: [label(f), value(f)],
                        ),
                      ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  for (var i = 0; i < figures.length; i++)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: i == 0
                              ? null
                              : BorderDirectional(
                                  start: BorderSide(color: p.border),
                                ),
                        ),
                        padding: const EdgeInsetsDirectional.only(
                          start: 12,
                          end: 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(figures[i]),
                            const SizedBox(height: 4),
                            value(figures[i]),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class LedgerModes<T> extends StatelessWidget {
  const LedgerModes({
    super.key,
    required this.options,
    required this.selected,
    required this.onChange,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChange;
  @override
  Widget build(BuildContext context) {
    final p = context.palette, primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: p.surface,
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == selected,
                child: InkWell(
                  onTap: () => onChange(entry.key),
                  child: Container(
                    alignment: Alignment.center,
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected == entry.key ? primary : p.border,
                          width: selected == entry.key ? 2 : .7,
                        ),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: entry.key == selected
                              ? primary
                              : p.textSecondary,
                          fontWeight: entry.key == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatusLabel extends StatelessWidget {
  const StatusLabel(
    this.label, {
    super.key,
    this.positive = false,
    this.attention = false,
  });
  final String label;
  final bool positive, attention;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color ink = positive
        ? p.success
        : attention
        ? p.expense
        : p.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: positive
            ? ink.withValues(alpha: .12)
            : attention
            ? p.expenseSoft
            : p.surfaceMuted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: ink),
        ),
      ),
    );
  }
}

class LedgerGlyph extends StatelessWidget {
  const LedgerGlyph(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.palette.textSecondary;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 18, color: ink),
    );
  }
}

Future<DateTime?> chooseLedgerDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 1900 ? initial.year : 1900),
      lastDate: DateTime(initial.year > 2200 ? initial.year : 2200, 12, 31),
    );
