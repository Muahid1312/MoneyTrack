import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ledger_components.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/providers.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../statistics/presentation/insight_details.dart';
import '../../settings/application/settings_controller.dart';
import '../application/ledger_month.dart';
import '../application/transaction_filter.dart';
import '../application/transactions_controller.dart';
import 'transaction_actions.dart';
import 'transactions_screen.dart';

final ledgerDateProvider = StateProvider<DateTime>(
  (ref) => Dates.dateOnly(ref.read(clockProvider)()),
);
final ledgerMonthProvider = Provider<LedgerMonth>((ref) {
  final month = ref.watch(
    ledgerDateProvider.select((d) => DateTime(d.year, d.month)),
  );
  return LedgerMonth(
    month,
    ref.watch(activityCurrencyProvider),
    ref.watch(activityEntriesProvider),
    ref.watch(walletsProvider).valueOrNull?.transfers ?? const [],
  );
});

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});
  @override
  ConsumerState<LedgerScreen> createState() => _LedgerState();
}

enum _LedgerView {
  daily('Daily'),
  calendar('Calendar'),
  weekly('Weekly'),
  monthly('Monthly'),
  total('Total');

  const _LedgerView(this.label);
  final String label;
}

class _LedgerState extends ConsumerState<LedgerScreen> {
  _LedgerView view = _LedgerView.calendar;
  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(ledgerDateProvider);
    final today = Dates.dateOnly(ref.watch(clockProvider)());
    final currency = ref.watch(activityCurrencyProvider);
    final month = ref.watch(ledgerMonthProvider);
    final state = ref.watch(transactionsProvider),
        walletState = ref.watch(walletsProvider);
    final walletNames = {
      for (final w in walletState.valueOrNull?.wallets ?? const <Wallet>[])
        w.id!: w.name,
    };
    final currencies = {
      currency,
      ...?walletState.valueOrNull?.wallets.map((w) => w.currency),
      ...ref.watch(allTransactionsProvider).map((t) => t.currency),
    };
    void select(DateTime d) => ref.read(ledgerDateProvider.notifier).state = d;
    final calendar = view == _LedgerView.calendar;
    final annual = view == _LedgerView.monthly;
    final entries = ref.watch(activityEntriesProvider);
    final span = annual
        ? DateSpan(DateTime(selected.year), DateTime(selected.year + 1))
        : DateSpan.month(selected);
    final annualTotals = annual
        ? FinanceCalculator.totals(entries, span: span)
        : null;
    void move(int direction) =>
        select(shiftLedgerMonth(selected, direction * (annual ? 12 : 1)));
    final days = calendar
        ? [selected.day]
        : (month.days.keys.toList()..sort((a, b) => b.compareTo(a)));
    final addDate = calendar
        ? selected
        : DateTime(
            selected.year,
            selected.month,
            selected.year == today.year && selected.month == today.month
                ? today.day
                : selected.day,
          );
    final future = addDate.isAfter(today);
    final monthTitle = annual
        ? DateFormat.y().format(selected)
        : DateFormat('MMMM y').format(selected);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              tooltip: annual ? 'Previous year' : 'Previous month',
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: TextButton(
                onPressed: () async {
                  final day = await chooseLedgerDate(context, selected);
                  if (mounted && day != null) select(day);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  minimumSize: const Size(44, 48),
                ),
                child: Text(
                  monthTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).appBarTheme.titleTextStyle,
                ),
              ),
            ),
            IconButton(
              tooltip: annual ? 'Next year' : 'Next month',
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<AppCurrency>(
            tooltip: 'Ledger currency',
            initialValue: currency,
            onSelected: (c) =>
                ref.read(activityCurrencyChoiceProvider.notifier).state = c,
            itemBuilder: (_) => [
              for (final c in currencies)
                PopupMenuItem(value: c, child: Text('${c.code} · ${c.name}')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(
                  currency.code,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Search all transactions',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Search all transactions')),
                  body: const TransactionsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: state.hasError || walletState.hasError
          ? Center(
              child: TextButton(
                onPressed: () {
                  ref.invalidate(transactionsProvider);
                  ref.invalidate(walletsProvider);
                },
                child: const Text('Retry loading the ledger'),
              ),
            )
          : state.isLoading || walletState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final scale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          final minWidth = 5 * 64.0 * scale;
                          final strip = LedgerModes<_LedgerView>(
                            options: {
                              for (final v in _LedgerView.values) v: v.label,
                            },
                            selected: view,
                            onChange: (v) => setState(() => view = v),
                          );
                          return minWidth > box.maxWidth
                              ? SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: minWidth,
                                    child: strip,
                                  ),
                                )
                              : strip;
                        },
                      ),
                      LedgerTotals(
                        income: annualTotals?.income ?? month.income,
                        expense: annualTotals?.expense ?? month.expense,
                        currency: currency,
                      ),
                      if (calendar)
                        _Calendar(
                          selected: selected,
                          today: today,
                          month: month,
                          currency: currency,
                          onSelect: select,
                        ),
                      if (future)
                        TextButton(
                          onPressed: () => select(today),
                          child: const Text('Go to today to record an entry'),
                        ),
                    ],
                  ),
                ),
                if (annual || view == _LedgerView.weekly)
                  SliverToBoxAdapter(
                    child: _LedgerPeriods(
                      month: selected,
                      annual: annual,
                      currency: currency,
                    ),
                  ),
                if (view == _LedgerView.total)
                  SliverToBoxAdapter(
                    child: _MonthComparison(
                      date: selected,
                      currency: currency,
                      month: month,
                    ),
                  ),
                if (calendar || view == _LedgerView.daily)
                  for (final n in days) ...[
                    SliverToBoxAdapter(
                      child: _DayHeader(
                        day: DateTime(selected.year, selected.month, n),
                        data: month.days[n],
                        currency: currency,
                      ),
                    ),
                    if (month.days[n] case final d?)
                      SliverList.builder(
                        itemCount: d.records.length,
                        itemBuilder: (_, i) => _RecordRow(
                          record: d.records[i],
                          names: walletNames,
                          currency: currency,
                        ),
                      )
                    else
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('No entries on this date.'),
                        ),
                      ),
                  ],
                if (view == _LedgerView.daily && days.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No entries this month.'),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 84)),
              ],
            ),
      floatingActionButton: future
          ? null
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => TransactionActions.openEditor(
                context,
                ref,
                preferredCurrency: currency,
                initialDate: addDate,
                onPosted: (date, postedCurrency) {
                  select(Dates.dateOnly(date));
                  ref.read(activityCurrencyChoiceProvider.notifier).state =
                      postedCurrency;
                },
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _LedgerPeriods extends ConsumerWidget {
  const _LedgerPeriods({
    required this.month,
    required this.annual,
    required this.currency,
  });
  final DateTime month;
  final bool annual;
  final AppCurrency currency;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthSpan = DateSpan.month(month);
    final weekOffset =
        (monthSpan.start.weekday % 7 -
            MaterialLocalizations.of(context).firstDayOfWeekIndex +
            7) %
        7;
    final period = annual
        ? DateSpan(DateTime(month.year), DateTime(month.year + 1))
        : DateSpan(Dates.addDays(monthSpan.start, -weekOffset), monthSpan.end);
    final entries = ref.watch(activityEntriesProvider);
    final buckets = FinanceCalculator.buckets(
      annual ? entries : entries.where((t) => monthSpan.contains(t.occurredAt)),
      period,
      annual ? BucketSize.month : BucketSize.week,
    );
    return Column(
      children: [
        for (final b in buckets)
          Builder(
            builder: (context) {
              final range = DateSpan(
                !annual && b.span.start.isBefore(monthSpan.start)
                    ? monthSpan.start
                    : b.span.start,
                b.span.end,
              );
              return ListTile(
                tileColor: context.palette.surface,
                title: Text(annual ? b.longLabel : Dates.spanLabel(range)),
                subtitle: Wrap(
                  spacing: 14,
                  children: [
                    Text(
                      'Income ${Money.format(b.income, currency)}',
                      style: TextStyle(color: context.palette.income),
                    ),
                    Text(
                      'Expenses ${Money.format(b.expense, currency)}',
                      style: TextStyle(color: context.palette.expense),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PeriodEntriesScreen(currency: currency, span: range),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MonthComparison extends ConsumerWidget {
  const _MonthComparison({
    required this.date,
    required this.currency,
    required this.month,
  });
  final DateTime date;
  final AppCurrency currency;
  final LedgerMonth month;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previous = DateSpan.month(DateTime(date.year, date.month - 1));
    final previousSpend = FinanceCalculator.totals(
      ref.watch(activityEntriesProvider),
      span: previous,
    ).expense;
    final settings = ref.watch(settingsProvider);
    final limit = currency == settings.currency
        ? settings.monthlyBudgetMinor
        : ref.watch(settingsRepositoryProvider).budgetFor(currency);
    final span = DateSpan.month(date);
    return Column(
      children: [
        ListTile(
          title: Text(Dates.spanLabel(span)),
          subtitle: const Text('Spending compared with last month'),
        ),
        FinancialSummary([
          (
            label: DateFormat.MMM().format(previous.start),
            value: Money.format(previousSpend, currency),
            color: null,
          ),
          (
            label: DateFormat.MMM().format(date),
            value: Money.format(month.expense, currency),
            color: null,
          ),
          (
            label: 'Change',
            value: Money.format(
              month.expense - previousSpend,
              currency,
              signed: true,
            ),
            color: null,
          ),
        ]),
        if (limit > 0)
          FinancialSummary([
            (
              label: 'Monthly limit',
              value: Money.format(limit, currency),
              color: null,
            ),
            (
              label: month.expense > limit ? 'Overspent' : 'Remaining',
              value: Money.format((limit - month.expense).abs(), currency),
              color: month.expense > limit ? context.palette.expense : null,
            ),
          ]),
        ListTile(
          title: const Text('View transactions'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  PeriodEntriesScreen(currency: currency, span: span),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.data,
    required this.currency,
  });
  final DateTime day;
  final LedgerDay? data;
  final AppCurrency currency;
  @override
  Widget build(BuildContext context) => Container(
    color: context.palette.surfaceMuted,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          DateFormat('EEE, MMM d').format(day),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (data case final d?)
          Wrap(
            spacing: 8,
            children: [
              if (d.income > 0)
                Text(
                  Money.format(d.income, currency, signed: true),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.palette.income,
                  ),
                ),
              if (d.expense > 0)
                Text(
                  Money.format(-d.expense, currency, signed: true),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.palette.expense,
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class LedgerTotals extends StatelessWidget {
  const LedgerTotals({
    super.key,
    required this.income,
    required this.expense,
    required this.currency,
  });
  final int income, expense;
  final AppCurrency currency;
  @override
  Widget build(BuildContext context) => FinancialSummary([
    (
      label: 'Income',
      value: Money.format(income, currency),
      color: context.palette.income,
    ),
    (
      label: 'Expenses',
      value: Money.format(expense, currency),
      color: context.palette.expense,
    ),
    (
      label: 'Net',
      value: Money.format(income - expense, currency),
      color: context.palette.textPrimary,
    ),
  ]);
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.selected,
    required this.today,
    required this.month,
    required this.currency,
    required this.onSelect,
  });
  final DateTime selected, today;
  final LedgerMonth month;
  final AppCurrency currency;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final first = DateTime(selected.year, selected.month);
    final offset = (first.weekday % 7 - local.firstDayOfWeekIndex + 7) % 7;
    final count = Dates.daysInMonth(first);
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.textScalerOf(context).scale(11) * 3 + 23;
    return Column(
      children: [
        Row(
          children: [
            for (var n = 0; n < 7; n++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E(
                      Localizations.localeOf(context).toString(),
                    ).format(
                      DateTime(
                        2023,
                        1,
                        1 + (local.firstDayOfWeekIndex + n) % 7,
                      ),
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        for (var week = 0; week < (offset + count + 6) ~/ 7; week++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (ctx) {
                      final number = week * 7 + col - offset + 1;
                      if (number < 1 || number > count) {
                        return SizedBox(height: height);
                      }
                      final date = DateTime(first.year, first.month, number);
                      final chosen = Dates.isSameDay(date, selected),
                          isToday = Dates.isSameDay(date, today);
                      final d = month.days[number];
                      return Semantics(
                        button: true,
                        selected: chosen,
                        onTap: () => onSelect(date),
                        label:
                            '${DateFormat.yMMMMd().format(date)}${isToday ? ", today" : ""}, income ${Money.format(d?.income ?? 0, currency)}, expenses ${Money.format(d?.expense ?? 0, currency)}',
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey('day-${date.toIso8601String()}'),
                          onTap: () => onSelect(date),
                          child: Container(
                            height: height,
                            alignment: Alignment.topCenter,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: chosen
                                  ? scheme.primaryContainer
                                  : context.palette.surface,
                              border: Border.all(
                                width: chosen ? 1 : 0.35,
                                color: chosen
                                    ? scheme.primary
                                    : context.palette.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chosen ? scheme.primary : null,
                                    borderRadius: BorderRadius.circular(4),
                                    border: isToday && !chosen
                                        ? Border.all(color: scheme.primary)
                                        : null,
                                  ),
                                  child: Text(
                                    '$number',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: chosen
                                              ? scheme.onPrimary
                                              : isToday
                                              ? scheme.primary
                                              : context.palette.textPrimary,
                                          decoration: isToday
                                              ? TextDecoration.underline
                                              : null,
                                          decorationColor: chosen
                                              ? scheme.onPrimary
                                              : scheme.primary,
                                          fontWeight: chosen || isToday
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ),
                                for (final val in [
                                  d?.income ?? 0,
                                  -(d?.expense ?? 0),
                                ])
                                  if (val != 0)
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${val > 0 ? "+" : ""}${Money.plain(val, currency)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: val > 0
                                                    ? context.palette.income
                                                    : context.palette.expense,
                                              ),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _RecordRow extends ConsumerWidget {
  const _RecordRow({
    required this.record,
    required this.names,
    required this.currency,
  });
  final LedgerRecord record;
  final Map<int, String> names;
  final AppCurrency currency;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = record.transaction;
    final transfer = record.transfer;
    final source = transfer?.sourceCurrency == currency;
    final amount =
        t?.signedMinor ??
        (source ? -transfer!.sourceMinor : transfer!.destinationMinor);
    final text =
        t == null && transfer!.sourceCurrency == transfer.destinationCurrency
        ? Money.format(transfer.sourceMinor, currency)
        : Money.format(amount, currency, signed: true);
    final color = t == null
        ? context.palette.textSecondary
        : t.type.isIncome
        ? context.palette.income
        : context.palette.expense;
    return Column(
      children: [
        ListTile(
          tileColor: context.palette.surface,
          dense: true,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: 5,
          leading: LedgerGlyph(
            t?.category.icon ?? Icons.swap_horiz,
            color: color,
          ),
          title: Text(t?.category.name ?? 'Transfer', maxLines: 2),
          subtitle: Text(
            t != null
                ? [
                    if (t.note.isNotEmpty) t.note,
                    names[t.walletId] ?? currency.code,
                  ].join(' · ')
                : '${names[transfer!.sourceId]} → ${names[transfer.destinationId]}',
          ),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .32,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
          ),
          onTap: () => t != null
              ? TransactionActions.showActions(context, ref, t)
              : Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => WalletDetailsScreen(
                      walletId: source
                          ? transfer!.sourceId
                          : transfer!.destinationId,
                    ),
                  ),
                ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
