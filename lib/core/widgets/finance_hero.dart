import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// The same currency-labelled balance surface is used across personal and fund ledgers.
class FinanceHero extends StatelessWidget {
  const FinanceHero({
    super.key,
    required this.label,
    required this.amount,
    this.action,
    this.details = const [],
  });
  final String label, amount;
  final Widget? action;
  final List<({String label, String value})> details;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: a.dark, borderRadius: AppRadii.hero),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: t.labelLarge?.copyWith(color: a.cardInk),
                  ),
                ),
                if (action != null)
                  IconTheme(
                    data: IconThemeData(color: a.cardInk),
                    child: action!,
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              amount,
              textDirection: TextDirection.ltr,
              style: AppTypography.amount(
                36,
                weight: FontWeight.w800,
                color: a.cardInk,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack =
                      constraints.maxWidth < 230 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19;
                  final itemWidth = stack
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final detail in details)
                        SizedBox(
                          width: itemWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.label,
                                style: t.labelMedium?.copyWith(color: a.light),
                              ),
                              Text(
                                detail.value,
                                textDirection: TextDirection.ltr,
                                style: AppTypography.amount(
                                  17,
                                  color: a.cardInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
