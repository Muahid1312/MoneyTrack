import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/categories.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/feedback.dart';
import '../../../data/models/wallet.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/providers.dart';
import '../../planning/application/planning_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../domain/wallet_budget.dart';

class WalletBudgetPanel extends ConsumerWidget {
  const WalletBudgetPanel({super.key, this.actions});
  final Widget? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletsProvider);
    final snapshot = state.valueOrNull;
    final wallet = ref.watch(selectedWalletProvider);
    if (snapshot == null || wallet == null) {
      if (state.hasError) {
        return TextButton(
          onPressed: () => ref.invalidate(walletsProvider),
          child: const Text('Retry loading wallets'),
        );
      }
      if (state.isLoading) return const LinearProgressIndicator();
      if (snapshot != null) {
        return OutlinedButton.icon(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Add a wallet'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const WalletEditorScreen()),
          ),
        );
      }
      return actions ?? const SizedBox.shrink();
    }
    final wallets = snapshot.wallets.where((w) => !w.archived);
    final hidden = ref.watch(settingsProvider).hideBalance;
    final now = ref.watch(clockProvider)();
    final transactions = ref.watch(transactionsProvider);
    String money(int n) => hidden ? '••••' : Money.format(n, wallet.currency);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: wallets.length == 1
                      ? Text(
                          '${wallet.name} · ${wallet.currency.code}',
                          style: Theme.of(context).textTheme.titleMedium,
                        )
                      : DropdownButton<int>(
                          isExpanded: true,
                          value: wallet.id,
                          items: [
                            for (final w in wallets)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text('${w.name} · ${w.currency.code}'),
                              ),
                          ],
                          onChanged: (id) {
                            if (id != null) selectWallet(ref, id);
                          },
                        ),
                ),
                IconButton(
                  tooltip: hidden ? 'Show balance' : 'Hide balance',
                  icon: Icon(
                    hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      ref.read(settingsProvider.notifier).toggleHideBalance(),
                ),
              ],
            ),
            if (actions != null &&
                wallets.where((w) => w.currency == wallet.currency).length >
                    1) ...[
              Text(
                'Total available · ${wallet.currency.code}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                money(
                  wallets
                      .where((w) => w.currency == wallet.currency)
                      .fold<int>(0, (n, w) => n + snapshot.available(w.id!)),
                ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Divider(height: 28),
            ],
            Text(
              actions == null
                  ? 'Available to spend'
                  : 'Available to spend · ${wallet.name}',
            ),
            Text(
              money(snapshot.available(wallet.id!)),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('Wallet cash   ${money(snapshot.balances[wallet.id]!)}'),
            Text(
              'Reserved savings   ${money(snapshot.reserved[wallet.id] ?? 0)}',
            ),
            if (actions != null) ...[const SizedBox(height: 16), actions!],
            const Divider(),
            ref
                .watch(planningProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => TextButton(
                    onPressed: () => ref.invalidate(planningProvider),
                    child: const Text('Retry wallet budgets'),
                  ),
                  data: (all) {
                    final budgets = (all?.budgets ?? const <WalletBudget>[])
                        .where((b) => b.walletId == wallet.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (budgets.isEmpty) const Text('No budget set'),
                        for (final b
                            in actions == null ? budgets : budgets.take(2))
                          _BudgetItem(
                            budget: b,
                            wallet: wallet,
                            now: now,
                            transactions: transactions,
                            money: money,
                            onEdit: () => _edit(context, wallet, b),
                          ),
                        if (actions != null && budgets.length > 2)
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Wallet budgets'),
                                  ),
                                  body: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: const [WalletBudgetPanel()],
                                  ),
                                ),
                              ),
                            ),
                            child: Text('View all ${budgets.length} budgets'),
                          ),
                      ],
                    );
                  },
                ),
            TextButton.icon(
              onPressed: () => _edit(context, wallet, null),
              icon: const Icon(Icons.add),
              label: const Text('Set a budget'),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(BuildContext context, Wallet wallet, WalletBudget? budget) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _BudgetForm(wallet, budget)),
      );
}

class _BudgetItem extends StatelessWidget {
  const _BudgetItem({
    required this.budget,
    required this.wallet,
    required this.now,
    required this.transactions,
    required this.money,
    required this.onEdit,
  });

  final WalletBudget budget;
  final Wallet wallet;
  final DateTime now;
  final AsyncValue<List<TransactionModel>> transactions;
  final String Function(int) money;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final last = budget.end;
    final ended = last != null && DateUtils.dateOnly(now).isAfter(last);
    final asOf = last != null && ended
        ? DateTime(
            last.year,
            last.month,
            last.day + 1,
          ).subtract(const Duration(microseconds: 1))
        : now;
    final status = transactions.hasValue
        ? budget.status(asOf, wallet.currency, transactions.requireValue)
        : null;
    final category = budget.category == null
        ? 'All expenses'
        : Categories.byId(budget.category!).name;
    final label = switch (budget.period) {
      BudgetPeriod.daily => 'Daily',
      BudgetPeriod.weekly => 'Weekly',
      BudgetPeriod.monthly => 'Monthly',
      BudgetPeriod.custom => 'Custom',
    };
    final dateFormat = DateFormat.yMMMd();
    final first = budget.period == BudgetPeriod.custom || status == null
        ? budget.start
        : periodStart(budget.period, asOf);
    final through = switch (budget.period) {
      BudgetPeriod.weekly => DateTime(first.year, first.month, first.day + 6),
      BudgetPeriod.monthly => DateTime(first.year, first.month + 1, 0),
      BudgetPeriod.custom => last!,
      BudgetPeriod.daily => first,
    };
    final summary = !transactions.hasValue
        ? 'Spending unavailable'
        : status == null
        ? 'Starts ${dateFormat.format(first)}'
        : status.remaining < 0
        ? '${money(-status.remaining)} over budget'
        : '${money(status.remaining)} left';
    return ExpansionTile(
      key: ValueKey(budget.id),
      tilePadding: EdgeInsets.zero,
      title: Text('$label · $category'),
      subtitle: Text(ended ? 'Ended · $summary' : summary),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            first == through
                ? dateFormat.format(first)
                : '${dateFormat.format(first)} – ${dateFormat.format(through)}',
          ),
        ),
        Text('Limit   ${money(budget.limit)}'),
        if (status != null) ...[
          if (budget.rollover) Text('Carried forward   ${money(status.carry)}'),
          Text('Spent   ${money(status.spent)}'),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (status.spent / (budget.limit + status.carry)).clamp(
              0.0,
              1.0,
            ),
            semanticsLabel: 'Budget used',
            semanticsValue: summary,
          ),
        ],
        TextButton(onPressed: onEdit, child: const Text('Edit budget')),
      ],
    );
  }
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm(this.wallet, this.budget);
  final Wallet wallet;
  final WalletBudget? budget;
  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  late BudgetPeriod period;
  late DateTime start, end;
  late bool rollover;
  String? category, error;
  late final TextEditingController limit;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    period = b?.period ?? BudgetPeriod.monthly;
    start = b?.start ?? ref.read(clockProvider)();
    end = b?.end ?? start;
    category = b?.category;
    rollover = b?.rollover ?? false;
    limit = TextEditingController(
      text: b == null ? '' : Money.plain(b.limit, widget.wallet.currency),
    );
  }

  @override
  void dispose() {
    limit.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (busy) return;
    if (remove &&
        !await confirmDestructive(
          context,
          title: 'Delete this budget?',
          message:
              'This removes the spending limit. Your wallet balance and transaction history stay the same.',
          confirmLabel: 'Delete budget',
        ))
      return;
    if (!mounted) return;
    final amount = Money.parseMinor(limit.text, widget.wallet.currency);
    if (!remove && (amount == null || amount <= 0)) {
      setState(
        () =>
            error = 'Enter a positive limit in ${widget.wallet.currency.code}.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(planningRepositoryProvider)!;
      if (remove) {
        await repo.removeBudget(widget.budget!.id!);
      } else {
        await repo.saveBudget(
          WalletBudget(
            id: widget.budget?.id,
            walletId: widget.wallet.id!,
            limit: amount!,
            period: period,
            start: periodStart(period, start),
            end: period == BudgetPeriod.custom ? DateUtils.dateOnly(end) : null,
            category: category,
            rollover: period != BudgetPeriod.custom && rollover,
          ),
        );
      }
      if (mounted) {
        ref.invalidate(planningProvider);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Check the limit, wallet and dates.';
        });
      }
    }
  }

  Future<void> _date(bool first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked != null && mounted) {
      setState(() {
        if (first) {
          start = picked;
          if (end.isBefore(start)) end = start;
        } else {
          end = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wallet budget')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${widget.wallet.name} · ${widget.wallet.currency.code}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'A spending limit leaves your wallet cash and savings untouched.',
        ),
        TextField(
          controller: limit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Spending limit (${widget.wallet.currency.code})',
          ),
        ),
        DropdownButtonFormField<BudgetPeriod>(
          initialValue: period,
          decoration: const InputDecoration(labelText: 'Period'),
          items: [
            for (final p in BudgetPeriod.values)
              DropdownMenuItem(
                value: p,
                child: Text(switch (p) {
                  BudgetPeriod.daily => 'Daily',
                  BudgetPeriod.weekly => 'Weekly',
                  BudgetPeriod.monthly => 'Monthly',
                  BudgetPeriod.custom => 'Choose dates',
                }),
              ),
          ],
          onChanged: (p) => setState(() => period = p!),
        ),
        DropdownButtonFormField<String>(
          initialValue: category ?? '',
          decoration: const InputDecoration(labelText: 'Expenses'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All expenses')),
            for (final c in Categories.expense)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (c) => setState(() => category = c == '' ? null : c),
        ),
        TextButton(
          onPressed: () => _date(true),
          child: Text(
            'Starts ${DateFormat.yMMMd().format(periodStart(period, start))}',
          ),
        ),
        if (period == BudgetPeriod.custom)
          TextButton(
            onPressed: () => _date(false),
            child: Text('Through ${DateFormat.yMMMd().format(end)}'),
          )
        else
          SwitchListTile(
            title: const Text('Carry forward unused money'),
            value: rollover,
            onChanged: (v) => setState(() => rollover = v),
          ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy ? null : () => _save(),
          child: const Text('Save budget'),
        ),
        if (widget.budget != null)
          TextButton(
            onPressed: busy ? null : () => _save(remove: true),
            child: const Text('Remove budget'),
          ),
      ],
    ),
  );
}
