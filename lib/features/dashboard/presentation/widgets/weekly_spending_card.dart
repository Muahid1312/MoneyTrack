import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/currency.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/animated_money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../statistics/domain/finance_calculator.dart';
import '../../application/dashboard_providers.dart';

class WeeklySpendingCard extends StatefulWidget {
  const WeeklySpendingCard({super.key, required this.data, required this.currency});

  final WeeklySpending data;
  final AppCurrency currency;

  @override
  State<WeeklySpendingCard> createState() => _WeeklySpendingCardState();
}

class _WeeklySpendingCardState extends State<WeeklySpendingCard> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final d = widget.data;
    final maxV = d.amounts.fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = maxV == 0 ? 1.0 : maxV * 1.15;
    final change = FinanceCalculator.percentChange(d.previousTotal, d.total);
    final selected = _touched;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected == null
                          ? 'Spent in the last 7 days'
                          : DateFormat('EEEE, MMM d').format(d.days[selected]),
                      style: t.labelMedium?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    AnimatedMoney(
                      minor: selected == null ? d.total : d.amounts[selected],
                      currency: widget.currency,
                      duration: AppDurations.medium,
                      style: AppTypography.amount(24, weight: FontWeight.w800, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              if (change != null) _ChangeBadge(change: change),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 3,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: p.chartGrid,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final isToday = i == 6;
                        final active = i == selected || (selected == null && isToday);
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: Text(
                            isToday ? 'Today' : DateFormat('E').format(d.days[i]),
                            style: t.labelSmall?.copyWith(
                              color: active ? p.textPrimary : p.textTertiary,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (!event.isInterestedForInteractions) {
                      if (_touched != null) setState(() => _touched = null);
                      return;
                    }
                    if (i != _touched) setState(() => _touched = i);
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.navy800,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    tooltipMargin: 8,
                    fitInsideHorizontally: true,
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      Money.format(d.amounts[gi], widget.currency),
                      AppTypography.amount(12.5, color: Colors.white),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < 7; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: d.amounts[i].toDouble(),
                          width: 22,
                          borderRadius: BorderRadius.circular(8),
                          gradient: (i == selected || (selected == null && i == 6))
                              ? const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [AppColors.emeraldDeep, AppColors.emeraldBright],
                                )
                              : null,
                          color: context.isDark
                              ? const Color(0xFF2A3A55)
                              : const Color(0xFFCFD8E3),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: p.chartTrack,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              duration: AppDurations.chart,
              curve: AppCurves.emphasized,
            ),
          ),
          if (maxV == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('No spending recorded this week — nice.',
                  style: t.bodySmall?.copyWith(color: p.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});
  final double change;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final up = change > 0;
    final color = up ? p.expense : p.income;
    return Tooltip(
      message: 'Compared with the previous 7 days',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: up ? p.expenseSoft : p.incomeSoft,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 14, color: color),
            const SizedBox(width: 3),
            Text('${change.abs().toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
