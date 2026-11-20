import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/categories.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/providers.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/domain/schedule.dart';
import '../../settings/application/settings_controller.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../domain/wallet_budget.dart';

class WalletBudgetPanel extends ConsumerStatefulWidget {
  const WalletBudgetPanel({super.key});
  @override
  ConsumerState<WalletBudgetPanel> createState() => _WalletBudgetPanelState();
}

class _WalletBudgetPanelState extends ConsumerState<WalletBudgetPanel> {
  int? walletId;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(walletsProvider).valueOrNull;
    if (snapshot == null) return const SizedBox.shrink();
    final wallets = snapshot.wallets.where((w) => !w.archived).toList();
    if (wallets.isEmpty) return const SizedBox.shrink();
    final wallet =
        wallets.where((w) => w.id == walletId).firstOrNull ?? wallets.first;
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
            Text(
              'How much can I spend today?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            DropdownButton<int>(
              isExpanded: true,
              value: wallet.id,
              items: [
                for (final w in wallets)
                  DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.name} · ${w.currency.code}'),
                  ),
              ],
              onChanged: (v) => setState(() => walletId = v),
            ),
            Text('Wallet cash   ${money(snapshot.balances[wallet.id]!)}'),
            Text(
              'Reserved savings   ${money(snapshot.reserved[wallet.id] ?? 0)}',
            ),
            Text(
              'Available cash   ${money(snapshot.available(wallet.id!))}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
                        if (budgets.isEmpty)
                          const Text('No spending limits for this wallet.'),
                        for (final b in budgets)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${b.period.name} · ${b.category == null ? 'All expenses' : Categories.byId(b.category!).name}',
                            ),
                            subtitle: Builder(
                              builder: (_) {
                                if (!transactions.hasValue) {
                                  return const Text('Spending unavailable');
                                }
                                final last = b.end;
                                final asOf =
                                    last != null &&
                                        DateUtils.dateOnly(now).isAfter(last)
                                    ? DateTime(
                                        last.year,
                                        last.month,
                                        last.day + 1,
                                      ).subtract(
                                        const Duration(microseconds: 1),
                                      )
                                    : now;
                                final ended = asOf != now;
                                final status = b.status(
                                  asOf,
                                  wallet.currency,
                                  transactions.requireValue,
                                );
                                if (status == null) {
                                  return Text(
                                    'Starts ${CivilSchedule.key(b.start)} · Limit ${money(b.limit)}',
                                  );
                                }
                                final first = b.period == BudgetPeriod.custom
                                    ? b.start
                                    : periodStart(b.period, asOf);
                                final through = switch (b.period) {
                                  BudgetPeriod.weekly => DateTime(
                                    first.year,
                                    first.month,
                                    first.day + 6,
                                  ),
                                  BudgetPeriod.monthly => DateTime(
                                    first.year,
                                    first.month + 1,
                                    0,
                                  ),
                                  BudgetPeriod.custom => last!,
                                  BudgetPeriod.daily => first,
                                };
                                return Text(
                                  [
                                    '${ended ? 'Ended · ' : ''}${CivilSchedule.key(first)}${first == through ? '' : ' – ${CivilSchedule.key(through)}'}',
                                    'Limit ${money(b.limit)}${b.rollover ? ' · Carried forward ${money(status.carry)}' : ''}',
                                    'Spent ${money(status.spent)} · Remaining ${money(status.remaining < 0 ? 0 : status.remaining)}',
                                    if (status.remaining < 0)
                                      'Overspent ${money(-status.remaining)}',
                                  ].join('\n'),
                                );
                              },
                            ),
                            onTap: () => _edit(wallet, b),
                          ),
                      ],
                    );
                  },
                ),
            TextButton.icon(
              onPressed: () => _edit(wallet, null),
              icon: const Icon(Icons.add),
              label: const Text('Wallet budget'),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(Wallet wallet, WalletBudget? budget) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => _BudgetForm(wallet, budget)));
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
            labelText: 'Period limit (${widget.wallet.currency.code})',
          ),
        ),
        DropdownButtonFormField<BudgetPeriod>(
          initialValue: period,
          decoration: const InputDecoration(labelText: 'Period'),
          items: [
            for (final p in BudgetPeriod.values)
              DropdownMenuItem(value: p, child: Text(p.name)),
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
