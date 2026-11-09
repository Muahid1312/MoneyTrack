import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/currency.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/money.dart';
import '../../domain/finance_calculator.dart';

/// "Nice" axis maximum and interval for integer minor-unit values.
({double max, double interval}) niceAxis(int maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return (max: 100.0, interval: 25.0);
  final raw = maxValue / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
  // Smallest multiple of step that leaves a little headroom above the data.
  final max = ((maxValue * 1.08) / step).ceil() * step;
  return (max: max.toDouble(), interval: step);
}

Widget _axisLabel(BuildContext context, String text, TitleMeta meta, {bool strong = false}) {
  final p = context.palette;
  return SideTitleWidget(
    meta: meta,
    space: 6,
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: strong ? p.textPrimary : p.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
    ),
  );
}

FlTitlesData _titles(
  BuildContext context, {
  required AppCurrency currency,
  required double interval,
  required double maxY,
  required String Function(int index) bottomLabel,
  required int count,
  int step = 1,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 46,
        interval: interval,
        getTitlesWidget: (v, meta) {
          if (v == 0 || v > maxY + 0.01) return const SizedBox.shrink();
          return _axisLabel(context, Money.compact(v.round(), currency), meta);
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= count || (v - i).abs() > 0.01) return const SizedBox.shrink();
          if (i % step != 0) return const SizedBox.shrink();
          return _axisLabel(context, bottomLabel(i), meta);
        },
      ),
    ),
  );
}

FlGridData _grid(BuildContext context, double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: context.palette.chartGrid, strokeWidth: 1, dashArray: [4, 4]),
    );

/// Grouped income vs. expense bars per bucket.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({super.key, required this.buckets, required this.currency});

  final List<PeriodBucket> buckets;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxV = buckets.fold<int>(0, (m, b) => math.max(m, math.max(b.income, b.expense)));
    final axis = niceAxis(maxV);
    final n = buckets.length;
    final rodW = (120 / math.max(n, 1)).clamp(5.0, 14.0);

    final chart = BarChart(
      BarChartData(
        maxY: axis.max,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        groupsSpace: 12,
        borderData: FlBorderData(show: false),
        gridData: _grid(context, axis.interval),
        titlesData: _titles(context,
            currency: currency,
            interval: axis.interval,
            maxY: axis.max,
            count: n,
            bottomLabel: (i) => buckets[i].label),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy800,
            tooltipBorderRadius: BorderRadius.circular(12),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, gi, rod, ri) {
              final b = buckets[gi];
              if (ri != 0) return null;
              return BarTooltipItem(
                '${b.longLabel}\n',
                Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white70),
                children: [
                  TextSpan(
                    text: 'In  ${Money.format(b.income, currency)}\n',
                    style: AppTypography.amount(12.5, color: AppColors.emeraldBright),
                  ),
                  TextSpan(
                    text: 'Out ${Money.format(b.expense, currency)}',
                    style: AppTypography.amount(12.5, color: AppColors.roseSoft),
                  ),
                ],
                textAlign: TextAlign.left,
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].income.toDouble(),
                  width: rodW,
                  borderRadius: BorderRadius.circular(rodW / 2.4),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [AppColors.emeraldDeep, AppColors.emeraldBright],
                  ),
                ),
                BarChartRodData(
                  toY: buckets[i].expense.toDouble(),
                  width: rodW,
                  borderRadius: BorderRadius.circular(rodW / 2.4),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [p.expense, Color.lerp(p.expense, Colors.white, 0.3)!],
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: AppDurations.chart,
      curve: AppCurves.emphasized,
    );

    return LayoutBuilder(builder: (context, c) {
      final minWidth = n * 46.0 + 46;
      if (minWidth <= c.maxWidth) return SizedBox(height: 210, child: chart);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: SizedBox(width: minWidth, height: 210, child: chart),
      );
    });
  }
}

/// Smooth spending trend line with gradient area and average guide.
class SpendingTrendChart extends StatelessWidget {
  const SpendingTrendChart({
    super.key,
    required this.buckets,
    required this.currency,
    required this.average,
  });

  final List<PeriodBucket> buckets;
  final AppCurrency currency;

  /// Average expense per bucket (minor units).
  final int average;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = buckets.length;
    final maxV = buckets.fold<int>(0, (m, b) => math.max(m, b.expense));
    final axis = niceAxis(maxV);
    final step = math.max(1, (n / 6).ceil());
    final lineColor = context.isDark ? AppColors.emeraldBright : AppColors.emerald;

    final spots = [
      for (var i = 0; i < n; i++) FlSpot(i.toDouble(), buckets[i].expense.toDouble()),
    ];

    return SizedBox(
      height: 210,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, n - 1).toDouble(),
          minY: 0,
          maxY: axis.max,
          borderData: FlBorderData(show: false),
          gridData: _grid(context, axis.interval),
          titlesData: _titles(context,
              currency: currency,
              interval: axis.interval,
              maxY: axis.max,
              count: n,
              step: step,
              bottomLabel: (i) => buckets[i].label),
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (average > 0)
              HorizontalLine(
                y: average.toDouble(),
                color: p.textTertiary.withValues(alpha: 0.7),
                strokeWidth: 1.2,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: p.textSecondary, letterSpacing: 0),
                  labelResolver: (_) => 'avg ${Money.compact(average, currency)}',
                ),
              ),
          ]),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            getTouchedSpotIndicator: (bar, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  FlLine(color: lineColor.withValues(alpha: 0.35), strokeWidth: 1.5, dashArray: [3, 3]),
                  FlDotData(
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 5.5,
                      color: p.surface,
                      strokeWidth: 3,
                      strokeColor: lineColor,
                    ),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.navy800,
              tooltipBorderRadius: BorderRadius.circular(12),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${buckets[s.x.round()].longLabel}\n',
                    Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white70),
                    children: [
                      TextSpan(
                        text: Money.format(buckets[s.x.round()].expense, currency),
                        style: AppTypography.amount(13.5, color: Colors.white),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: n == 1 ? [spots.first, FlSpot(1, spots.first.y)] : spots,
              isCurved: true,
              curveSmoothness: 0.28,
              preventCurveOverShooting: true,
              barWidth: 3,
              isStrokeCapRound: true,
              color: lineColor,
              shadow: Shadow(color: lineColor.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 6)),
              dotData: FlDotData(show: n <= 12, getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: p.surface,
                    strokeWidth: 2,
                    strokeColor: lineColor,
                  )),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: context.isDark ? 0.28 : 0.22),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: AppDurations.chart,
        curve: AppCurves.emphasized,
      ),
    );
  }
}

/// Interactive donut. Touching a slice raises it and reports the index.
class ExpenseDonut extends StatelessWidget {
  const ExpenseDonut({
    super.key,
    required this.shares,
    required this.selected,
    required this.onSelect,
    required this.center,
    this.size = 220,
  });

  final List<CategoryShare> shares;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final Widget center;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ring = size * 0.15;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: shares.length > 1 ? 3 : 0,
              centerSpaceRadius: size / 2 - ring - 8,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final i = response?.touchedSection?.touchedSectionIndex;
                  if (event is FlTapUpEvent) {
                    onSelect(i == null || i < 0 || i == selected ? null : i);
                  }
                },
              ),
              sections: [
                for (var i = 0; i < shares.length; i++)
                  PieChartSectionData(
                    value: shares[i].amountMinor.toDouble(),
                    color: selected == null || selected == i
                        ? shares[i].category.color
                        : shares[i].category.color.withValues(alpha: 0.28),
                    radius: selected == i ? ring + 8 : ring,
                    showTitle: false,
                    borderSide: BorderSide(color: p.surface, width: 0),
                  ),
              ],
            ),
            duration: AppDurations.chart,
            curve: AppCurves.emphasized,
          ),
          Padding(padding: EdgeInsets.all(ring + 18), child: center),
        ],
      ),
    );
  }
}
