import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../../data/repositories/providers.dart';
import '../../budgets/application/budget_providers.dart';
import '../../budgets/presentation/budget_screen.dart';
import '../../projects/application/project_providers.dart';
import '../../projects/presentation/projects_screen.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../../wallets/application/wallet_providers.dart';
import '../application/statistics_providers.dart';
import '../domain/cash_history.dart';

class PeriodEntriesScreen extends ConsumerWidget {
  const PeriodEntriesScreen({
    super.key,
    required this.currency,
    required this.span,
    this.category,
  });
  final AppCurrency currency;
  final DateSpan span;
  final String? category;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionsProvider);
    final wallets = ref.watch(walletsProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Contributing transactions')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(transactionsProvider),
            child: const Text('Retry loading transactions'),
          ),
        ),
        data: (all) {
          final records = all
              .where(
                (tx) =>
                    tx.currency == currency &&
                    span.contains(tx.occurredAt) &&
                    (category == null || category == tx.categoryId),
              )
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: records.length + 1,
            itemBuilder: (context, i) {
              if (i == 0)
                return ListTile(
                  title: Text('${currency.code} · ${Dates.spanLabel(span)}'),
                  subtitle: Text('${records.length} entries'),
                );
              final tx = records[i - 1];
              return TransactionTile(
                transaction: tx,
                currency: currency,
                showDate: true,
                walletName: wallets?.wallets
                    .where((w) => w.id == tx.walletId)
                    .firstOrNull
                    ?.name,
                onTap: () => TransactionActions.showActions(context, ref, tx),
              );
            },
          );
        },
      ),
    );
  }
}

class InsightDetails extends ConsumerWidget {
  const InsightDetails({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final budget = ref.watch(budgetStatusProvider);
    final span = ref.watch(statsRangeProvider).span;
    final wallets = ref.watch(walletsProvider);
    final txs = ref.watch(transactionsProvider);
    final projects = ref.watch(projectsProvider).valueOrNull?.projects;
    final points = wallets.valueOrNull == null || !txs.hasValue
        ? null
        : cashHistory(
            wallets.requireValue!,
            txs.requireValue,
            currency,
            span,
            ref.watch(clockProvider)(),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View contributing transactions'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  PeriodEntriesScreen(currency: currency, span: span),
            ),
          ),
        ),
        if (points != null && points.isNotEmpty)
          Card(
            child: ExpansionTile(
              title: const Text('Wallet cash over time'),
              subtitle: Text(
                '${DateFormat.MMMd().format(points.last.day)} · ${Money.format(points.last.minor, currency)} ${currency.code}',
              ),
              children: [
                for (final p in points)
                  ListTile(
                    dense: true,
                    title: Text(DateFormat.yMMMd().format(p.day)),
                    trailing: Text(Money.format(p.minor, currency)),
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Calculated from today’s opening balances and dated transactions, transfers and debt payments. Includes savings held in wallets.',
                  ),
                ),
              ],
            ),
          ),
        if (budget.hasBudget)
          ListTile(
            leading: const Icon(Icons.track_changes),
            title: const Text('Current monthly spending limit'),
            subtitle: Text(
              '${Money.format(budget.spentMinor, currency)} spent · ${Money.format(budget.remainingMinor.abs(), currency)} ${budget.remainingMinor < 0 ? "over" : "left"}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, BudgetScreen.route()),
          ),
        if (projects != null && projects.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Project finances'),
            subtitle: Text(
              '${projects.length} projects · Income, expenses and net result',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ProjectsScreen()),
            ),
          ),
      ],
    );
  }
}
