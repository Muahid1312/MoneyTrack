import 'package:flutter/material.dart';

import '../../../../core/constants/categories.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/pressable.dart';
import '../../application/transaction_filter.dart';

/// Multi-select category filter. Resolves to the new selection, or null if
/// dismissed.
Future<Set<String>?> showCategoryFilterSheet(BuildContext context, Set<String> initial) {
  return showAppSheet<Set<String>>(
    context,
    builder: (_) => _CategorySheet(initial: initial),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.initial});
  final Set<String> initial;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    Widget grid(String title, List<TransactionCategory> cats) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              child: Text(title, style: AppTypography.overline(p.textSecondary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 86).floor().clamp(3, 6);
                final w = c.maxWidth / cols;
                return Wrap(
                  children: [
                    for (final cat in cats)
                      SizedBox(
                        width: w,
                        child: Semantics(
                          selected: _selected.contains(cat.id),
                          button: true,
                          label: cat.name,
                          excludeSemantics: true,
                          child: Pressable(
                            haptic: true,
                            scale: 0.92,
                            onTap: () => setState(() {
                              _selected.contains(cat.id)
                                  ? _selected.remove(cat.id)
                                  : _selected.add(cat.id);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  CategoryAvatar(
                                      category: cat,
                                      size: 48,
                                      selected: _selected.contains(cat.id)),
                                  const SizedBox(height: 6),
                                  Text(cat.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.labelSmall?.copyWith(
                                        color: _selected.contains(cat.id)
                                            ? p.textPrimary
                                            : p.textSecondary,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Categories',
          subtitle: _selected.isEmpty
              ? 'Showing all categories'
              : '${_selected.length} selected',
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                grid('EXPENSES', Categories.expense),
                grid('INCOME', Categories.income),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Clear',
                  onPressed: () => Navigator.of(context).pop(<String>{}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: 'Apply',
                  height: 52,
                  onPressed: () => Navigator.of(context).pop(_selected),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Date filter options. Resolves to an updated filter, or null if dismissed.
Future<TransactionFilter?> showDateFilterSheet(
    BuildContext context, TransactionFilter current) async {
  final choice = await showAppSheet<DateFilter>(
    context,
    builder: (ctx) {
      final p = ctx.palette;
      final t = Theme.of(ctx).textTheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Date range'),
          const SizedBox(height: 8),
          for (final d in DateFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Pressable(
                onTap: () => Navigator.of(ctx).pop(d),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: d == current.date
                        ? AppColors.emerald.withValues(alpha: ctx.isDark ? 0.14 : 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        d == DateFilter.custom
                            ? Icons.date_range_rounded
                            : Icons.calendar_today_rounded,
                        size: 19,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          d == DateFilter.custom && current.customSpan != null
                              ? '${d.label} · ${Dates.spanLabel(current.customSpan!)}'
                              : d.label,
                          style: t.titleSmall,
                        ),
                      ),
                      if (d == current.date)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.emerald, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
  if (choice == null || !context.mounted) return null;
  if (choice != DateFilter.custom) {
    return current.copyWith(date: choice, customSpan: () => null);
  }
  final now = DateTime.now();
  final initial = current.customSpan;
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: now,
    initialDateRange: initial == null
        ? null
        : DateTimeRange(start: initial.start, end: initial.lastDay),
    helpText: 'Filter by date',
    saveText: 'Apply',
  );
  if (range == null) return null;
  return current.copyWith(
    date: DateFilter.custom,
    customSpan: () => DateSpan.inclusive(range.start, range.end),
  );
}
