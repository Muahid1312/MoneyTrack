import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_shell.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/progress.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../application/statistics_providers.dart';
import '../domain/finance_calculator.dart';
import 'widgets/stat_charts.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    final now = ref.read(clockProvider)();
    final current = ref.read(statsRangeProvider).span;
    final last = current.lastDay.isAfter(now) ? now : current.lastDay;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(
          start: current.start.isAfter(last) ? last : current.start, end: last),
      helpText: 'Statistics period',
      saveText: 'Apply',
    );
    if (range != null) {
      ref.read(statsRangeProvider.notifier).custom(DateSpan.inclusive(range.start, range.end));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final range = ref.watch(statsRangeProvider);
    final data = ref.watch(statisticsProvider);
    final currency = ref.watch(currencyProvider);

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Statistics', style: t.headlineMedium),
                  Text('${currency.code} only · original amounts', style: t.labelMedium),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: AppDurations.medium,
                    child: Text(
                      Dates.spanLabel(data.span),
                      key: ValueKey(data.span),
                      style: t.bodyMedium?.copyWith(color: p.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              itemCount: RangePreset.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final preset = RangePreset.values[i];
                return AppChip(
                  label: preset.label,
                  icon: preset == RangePreset.custom ? Icons.date_range_rounded : null,
                  selected: range.preset == preset,
                  onTap: () => preset == RangePreset.custom
                      ? _pickCustom(context, ref)
                      : ref.read(statsRangeProvider.notifier).select(preset),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.screen, AppSpacing.xl, AppSpacing.screen, AppShell.contentBottomInset(context)),
          sliver: SliverList.list(
            children: data.isEmpty
                ? [
                    _OverviewCard(data: data, currency: currency),
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'Nothing to analyze yet',
                        message:
                            'There are no transactions in this period. Add some or choose a wider range to see charts and insights.',
                        actionLabel: 'Add transaction',
                        onAction: () => TransactionActions.openEditor(context, ref),
                      ),
                    ),
                  ]
                : [
                    _OverviewCard(data: data, currency: currency),
                    const SizedBox(height: AppSpacing.lg),
                    _InsightRow(data: data, currency: currency),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Income vs. expenses',
                      subtitle: data.flowBucketSize == BucketSize.week ? 'By week' : 'By month',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
                      child: Column(
                        children: [
                          IncomeExpenseChart(buckets: data.flowBuckets, currency: currency),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _Legend(color: AppColors.emerald, label: 'Income'),
                              const SizedBox(width: 20),
                              _Legend(color: p.expense, label: 'Expenses'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Spending trend',
                      subtitle: switch (data.trendBucketSize) {
                        BucketSize.day => 'Daily expenses · touch to inspect',
                        BucketSize.week => 'Weekly expenses · touch to inspect',
                        BucketSize.month => 'Monthly expenses · touch to inspect',
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(12, 22, 18, 12),
                      child: SpendingTrendChart(
                        buckets: data.trend,
                        currency: currency,
                        average: data.trend.isEmpty
                            ? 0
                            : (data.totals.expense * 2 + data.trend.length) ~/ (2 * data.trend.length),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const SectionHeader(title: 'Expense breakdown', subtitle: 'Tap a slice or row'),
                    const SizedBox(height: AppSpacing.md),
                    _BreakdownCard(shares: data.categories, total: data.totals.expense, currency: currency),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Monthly comparison',
                      subtitle:
                          '${DateFormat('MMMM').format(data.comparison.currentLabel.start)} vs. ${DateFormat('MMMM').format(data.comparison.previousLabel.start)}',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ComparisonCard(cmp: data.comparison, currency: currency),
                  ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: context.palette.textSecondary)),
        ],
      );
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data, required this.currency});
  final StatisticsData data;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final totals = data.totals;
    final savingsRate = totals.income == 0 ? null : (totals.net / totals.income * 100);
    final flowTotal = totals.income + totals.expense;
    final inShare = flowTotal == 0 ? 0.5 : totals.income / flowTotal;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadii.hero,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2B3E), AppColors.navy900],
        ),
        boxShadow: AppShadows.hero(context),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Net cash flow',
                  style: t.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.65))),
              const Spacer(),
              if (savingsRate != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: (savingsRate >= 0 ? AppColors.emerald : AppColors.rose)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${savingsRate.toStringAsFixed(0)}% saved',
                    style: t.labelSmall?.copyWith(
                        color: savingsRate >= 0 ? AppColors.emeraldBright : AppColors.roseSoft),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              minor: totals.net,
              currency: currency,
              signed: true,
              style: AppTypography.amount(32, weight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          // Split bar: share of income vs. expense in total flow.
          TweenAnimationBuilder<double>(
            tween: Tween(end: inShare),
            duration: AppDurations.chart,
            curve: AppCurves.emphasized,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: (v * 1000).round().clamp(1, 999),
                      child: Container(color: AppColors.emeraldBright),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      flex: ((1 - v) * 1000).round().clamp(1, 999),
                      child: Container(color: AppColors.roseSoft),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                    label: 'Income', minor: totals.income, color: AppColors.emeraldBright, currency: currency),
              ),
              Expanded(
                child: _MiniStat(
                    label: 'Expenses', minor: totals.expense, color: AppColors.roseSoft, currency: currency),
              ),
              _MiniCount(count: totals.count),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.minor, required this.color, required this.currency});
  final String label;
  final int minor;
  final Color color;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedMoney(
            minor: minor,
            currency: currency,
            style: AppTypography.amount(15, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Entries', style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
        const SizedBox(height: 4),
        Text('$count', style: AppTypography.amount(15, color: Colors.white)),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.data, required this.currency});
  final StatisticsData data;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final top = data.topCategory;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (top != null)
                    CategoryAvatar(category: top.category, size: 36)
                  else
                    Icon(Icons.emoji_events_outlined, color: p.textTertiary),
                  const SizedBox(height: 12),
                  Text('Top category', style: t.labelMedium?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: 2),
                  Text(top?.category.name ?? 'No expenses',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (top != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${Money.format(top.amountMinor, currency)} · ${(top.fraction * 100).toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: context.isDark ? 0.16 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.today_outlined,
                        size: 18,
                        color: context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep),
                  ),
                  const SizedBox(height: 12),
                  Text('Average per day', style: t.labelMedium?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedMoney(
                      minor: data.averageDailyExpense,
                      currency: currency,
                      style: AppTypography.amount(17, color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('in expenses',
                      style: t.labelSmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({required this.shares, required this.total, required this.currency});
  final List<CategoryShare> shares;
  final int total;
  final AppCurrency currency;

  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  int? _selected;

  @override
  void didUpdateWidget(_BreakdownCard old) {
    super.didUpdateWidget(old);
    if (_selected != null && _selected! >= widget.shares.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (widget.shares.isEmpty) {
      return const AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.pie_chart_outline_rounded,
          title: 'No expenses in this period',
          message: 'Only income was recorded. Expenses will be broken down here.',
        ),
      );
    }
    final sel = _selected == null ? null : widget.shares[_selected!];
    return AppCard(
      child: Column(
        children: [
          ExpenseDonut(
            shares: widget.shares,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
            center: AnimatedSwitcher(
              duration: AppDurations.fast,
              child: Column(
                key: ValueKey(_selected),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sel?.category.name ?? 'Total spent',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: t.labelMedium?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Money.format(sel?.amountMinor ?? widget.total, widget.currency),
                      style: AppTypography.amount(20, weight: FontWeight.w800, color: p.textPrimary),
                    ),
                  ),
                  if (sel != null)
                    Text('${(sel.fraction * 100).toStringAsFixed(1)}%',
                        style: t.labelMedium?.copyWith(color: sel.category.color)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < widget.shares.length; i++)
            _CategoryRow(
              share: widget.shares[i],
              currency: widget.currency,
              maxFraction: widget.shares.first.fraction,
              selected: _selected == i,
              dimmed: _selected != null && _selected != i,
              onTap: () => setState(() => _selected = _selected == i ? null : i),
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.share,
    required this.currency,
    required this.maxFraction,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final CategoryShare share;
  final AppCurrency currency;
  final double maxFraction;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${share.category.name}, ${Money.format(share.amountMinor, currency)}, ${(share.fraction * 100).toStringAsFixed(0)} percent',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: dimmed ? 0.45 : 1,
          child: AnimatedContainer(
            duration: AppDurations.medium,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? share.category.color.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CategoryAvatar(category: share.category, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(share.category.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                          ),
                          Text(Money.format(share.amountMinor, currency),
                              style: AppTypography.amount(14, color: p.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedProgressBar(
                              value: maxFraction == 0 ? 0 : share.fraction / maxFraction,
                              color: share.category.color,
                              height: 6,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 64,
                            child: Text(
                              '${(share.fraction * 100).toStringAsFixed(0)}% · ${share.count}×',
                              textAlign: TextAlign.right,
                              style: t.labelSmall?.copyWith(color: p.textSecondary, letterSpacing: 0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.cmp, required this.currency});
  final MonthComparison cmp;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxV = [
      cmp.current.income,
      cmp.current.expense,
      cmp.previous.income,
      cmp.previous.expense,
    ].reduce((a, b) => a > b ? a : b);
    final curName = DateFormat('MMM').format(cmp.currentLabel.start);
    final prevName = DateFormat('MMM').format(cmp.previousLabel.start);

    Widget block(String title, int cur, int prev, double? change, Color color, bool upIsGood) {
      final t = Theme.of(context).textTheme;
      final good = change == null ? null : (change > 0) == upIsGood || change == 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: good! ? p.incomeSoft : p.expenseSoft,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${change > 0 ? '+' : ''}${change.toStringAsFixed(0)}%',
                    style: t.labelSmall?.copyWith(color: good ? p.income : p.expense),
                  ),
                )
              else
                Text('No prior data', style: t.labelSmall?.copyWith(color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          _CompareBar(label: curName, value: cur, max: maxV, color: color, currency: currency),
          const SizedBox(height: 8),
          _CompareBar(
              label: prevName,
              value: prev,
              max: maxV,
              color: color.withValues(alpha: 0.35),
              currency: currency),
        ],
      );
    }

    return AppCard(
      child: Column(
        children: [
          block('Expenses', cmp.current.expense, cmp.previous.expense, cmp.expenseChange,
              p.expense, false),
          const SizedBox(height: 20),
          Divider(color: p.border),
          const SizedBox(height: 20),
          block('Income', cmp.current.income, cmp.previous.income, cmp.incomeChange,
              AppColors.emerald, true),
        ],
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.currency,
  });

  final String label;
  final int value;
  final int max;
  final Color color;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: t.labelMedium?.copyWith(color: p.textSecondary)),
        ),
        Expanded(
          child: AnimatedProgressBar(
            value: max == 0 ? 0 : value / max,
            color: color,
            height: 12,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(Money.format(value, currency),
                style: AppTypography.amount(13, color: p.textPrimary)),
          ),
        ),
      ],
    );
  }
}
