import 'package:flutter/material.dart';

import '../../../../core/constants/currency.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/animated_money.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../statistics/domain/finance_calculator.dart';

/// The dashboard centerpiece: midnight card with emerald glow.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balanceMinor,
    required this.month,
    required this.previousMonth,
    required this.currency,
    required this.hidden,
    required this.onToggleHidden,
    required this.monthLabel,
  });

  final int balanceMinor;
  final Totals month;
  final Totals previousMonth;
  final AppCurrency currency;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final net = month.net;
    final change = FinanceCalculator.percentChange(previousMonth.expense, month.expense);

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadii.hero,
        boxShadow: AppShadows.hero(context),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.hero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F2B3E), AppColors.navy900, Color(0xFF0B1220)],
              stops: [0, 0.55, 1],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            borderRadius: AppRadii.hero,
          ),
          child: CustomPaint(
            painter: _CardDecorPainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('Wallet cash',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.68))),
                      ),
                      const SizedBox(width: 6),
                      Pressable(
                        onTap: onToggleHidden,
                        scale: 0.85,
                        semanticLabel: hidden ? 'Show balance' : 'Hide balance',
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Text(currency.code,
                            style: t.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                letterSpacing: 0.8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedMoney(
                      minor: balanceMinor,
                      currency: currency,
                      obscured: hidden,
                      style: AppTypography.amount(38, weight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        icon: net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        color: net >= 0 ? AppColors.emeraldBright : AppColors.roseSoft,
                        text: hidden
                            ? 'Cash flow · $monthLabel'
                            : '${Money.format(net, currency, signed: true)} cash flow in $monthLabel',
                      ),
                      if (change != null)
                        _Pill(
                          icon: change <= 0
                              ? Icons.south_east_rounded
                              : Icons.north_east_rounded,
                          color: change <= 0 ? AppColors.emeraldBright : AppColors.amber,
                          text:
                              'Spending ${change <= 0 ? '−' : '+'}${change.abs().toStringAsFixed(0)}% vs prior month',
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _FlowStat(
                              label: 'Income',
                              minor: month.income,
                              currency: currency,
                              hidden: hidden,
                              icon: Icons.south_west_rounded,
                              color: AppColors.emeraldBright,
                            ),
                          ),
                          VerticalDivider(
                            width: 24,
                            thickness: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          Expanded(
                            child: _FlowStat(
                              label: 'Expenses',
                              minor: month.expense,
                              currency: currency,
                              hidden: hidden,
                              icon: Icons.north_east_rounded,
                              color: AppColors.roseSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: color, letterSpacing: 0.1)),
          ),
        ],
      ),
    );
  }
}

class _FlowStat extends StatelessWidget {
  const _FlowStat({
    required this.label,
    required this.minor,
    required this.currency,
    required this.hidden,
    required this.icon,
    required this.color,
  });

  final String label;
  final int minor;
  final AppCurrency currency;
  final bool hidden;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoney(
                  minor: minor,
                  currency: currency,
                  obscured: hidden,
                  style: AppTypography.amount(15.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Emerald glow, fine concentric rings and a faint mesh — decorative only.
class _CardDecorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * 0.92, size.height * 0.02);
    canvas.drawCircle(
      glowCenter,
      size.width * 0.55,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.emerald.withValues(alpha: 0.30),
          AppColors.emerald.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: glowCenter, radius: size.width * 0.55)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.045);
    final ringCenter = Offset(size.width * 1.02, size.height * 0.08);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(ringCenter, 46.0 * i, ring);
    }

    final low = Offset(size.width * 0.05, size.height * 1.05);
    canvas.drawCircle(
      low,
      size.width * 0.45,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.10),
          const Color(0xFF3B82F6).withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: low, radius: size.width * 0.45)),
    );

    // Subtle diagonal sheen.
    final sheen = Path()
      ..moveTo(size.width * 0.35, 0)
      ..lineTo(size.width * 0.55, 0)
      ..lineTo(size.width * 0.25, size.height)
      ..lineTo(size.width * 0.05, size.height)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.035), Colors.white.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
