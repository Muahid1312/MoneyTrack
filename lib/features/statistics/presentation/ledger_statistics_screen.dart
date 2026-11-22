import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/ledger_screen.dart';
import '../../wallets/application/wallet_providers.dart';
import '../domain/finance_calculator.dart';
import 'insight_details.dart';
import 'statistics_screen.dart';
import 'widgets/stat_charts.dart';

class LedgerStatisticsScreen extends ConsumerStatefulWidget {
  const LedgerStatisticsScreen({super.key});
  @override
  ConsumerState<LedgerStatisticsScreen> createState() => _StatsState();
}

class _StatsState extends ConsumerState<LedgerStatisticsScreen> {
  late DateTime month;
  bool income = false;
  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final span = DateSpan.month(month);
    final entries = ref.watch(reportingTransactionsProvider);
    final data = ref.watch(transactionsProvider);
    final totals = FinanceCalculator.totals(entries, span: span);
    final groups = FinanceCalculator.categoryDistribution(
      entries,
      span,
      income: income,
    );
    void drill(int i) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PeriodEntriesScreen(
          currency: currency,
          span: span,
          category: groups[i].category.id,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          PopupMenuButton<AppCurrency>(
            tooltip: 'Reporting currency',
            initialValue: currency,
            itemBuilder: (_) => [
              for (final c in AppCurrency.values)
                PopupMenuItem(value: c, child: Text(c.code)),
            ],
            onSelected: (c) =>
                ref.read(settingsProvider.notifier).setCurrency(c),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(currency.code),
              ),
            ),
          ),
        ],
      ),
      body: data.hasError
          ? Center(
              child: TextButton(
                onPressed: () => ref.invalidate(transactionsProvider),
                child: const Text('Retry statistics'),
              ),
            )
          : data.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous statistics month',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(
                        () => month = DateTime(month.year, month.month - 1),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        DateFormat('MMMM y').format(month),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next statistics month',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(
                        () => month = DateTime(month.year, month.month + 1),
                      ),
                    ),
                  ],
                ),
                LedgerTotals(
                  income: totals.income,
                  expense: totals.expense,
                  currency: currency,
                ),
                const Divider(height: 1),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Expenses'),
                      selected: !income,
                      onSelected: (_) => setState(() => income = false),
                    ),
                    ChoiceChip(
                      label: const Text('Income'),
                      selected: income,
                      onSelected: (_) => setState(() => income = true),
                    ),
                  ],
                ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        income
                            ? 'No income this month.'
                            : 'No expenses this month.',
                      ),
                    ),
                  )
                else ...[
                  Center(
                    child: ExpenseDonut(
                      size: 148,
                      shares: groups,
                      selected: null,
                      onSelect: (i) {
                        if (i != null) drill(i);
                      },
                      center: Text(income ? 'Income' : 'Expenses'),
                    ),
                  ),
                  for (var i = 0; i < groups.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        groups[i].category.icon,
                        color: groups[i].category.color,
                      ),
                      title: Text(groups[i].category.name),
                      subtitle: Text(
                        '${(groups[i].fraction * 100).toStringAsFixed(1)}%',
                      ),
                      trailing: Text(
                        Money.format(groups[i].amountMinor, currency),
                      ),
                      onTap: () => drill(i),
                    ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.show_chart),
                  title: const Text('Trends and comparisons'),
                  subtitle: const Text(
                    'Custom periods, spending, cash history and project finances',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Trends and comparisons'),
                        ),
                        body: const StatisticsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
