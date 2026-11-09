import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/wallet.dart';
import '../../planning/presentation/planning_screens.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../application/wallet_providers.dart';
import '../domain/exchange_rate.dart';

class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(walletsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wallets'), actions: [
        IconButton(tooltip: 'Transfer money', icon: const Icon(Icons.swap_horiz),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const TransferScreen()))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context), icon: const Icon(Icons.add),
        label: const Text('New wallet')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Failure(onRetry: () => ref.invalidate(walletsProvider)),
        data: (snapshot) {
          if (snapshot == null) return const Center(child: Text('Wallet storage is unavailable'));
          return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
            Text('Balances by currency', style: Theme.of(context).textTheme.titleMedium),
            const Text('Original amounts · no exchange rates applied'),
            const SizedBox(height: 12),
            for (final entry in ref.watch(currencyBalancesProvider).entries)
              ListTile(title: Text(entry.key.code),
                trailing: Text(Money.format(entry.value, entry.key))),
            const Divider(),
            if (snapshot.wallets.isEmpty) const Padding(padding: EdgeInsets.all(24),
              child: Text('Create your first wallet to start tracking.')),
            for (final wallet in snapshot.wallets)
              Card(child: ListTile(
                leading: Icon(wallet.archived ? Icons.archive_outlined : Icons.account_balance_wallet_outlined,
                    color: AppColors.emerald),
                title: Text(wallet.name),
                subtitle: Text('${wallet.type.label} · ${wallet.currency.code}${wallet.archived ? ' · Archived' : ''}\nAvailable ${Money.format(snapshot.available(wallet.id!), wallet.currency)} · Reserved ${Money.format(snapshot.reserved[wallet.id] ?? 0, wallet.currency)}'),
                trailing: Text(Money.format(snapshot.balances[wallet.id]!, wallet.currency)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => WalletDetailsScreen(walletId: wallet.id!))),
              )),
          ]);
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, [Wallet? wallet]) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WalletEditorScreen(wallet: wallet)));
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      const Text('Could not load wallets. Your stored data is unchanged.'),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ]));
}

class WalletEditorScreen extends ConsumerStatefulWidget {
  const WalletEditorScreen({super.key, this.wallet});
  final Wallet? wallet;
  @override
  ConsumerState<WalletEditorScreen> createState() => _WalletEditorState();
}

class _WalletEditorState extends ConsumerState<WalletEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  late WalletType _type;
  late AppCurrency _currency;
  late bool _archived;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final w = widget.wallet;
    _name = TextEditingController(text: w?.name ?? '');
    _currency = w?.currency ?? AppCurrency.usd;
    _opening = TextEditingController(text: Money.plain(w?.openingMinor ?? 0, _currency));
    _type = w?.type ?? WalletType.cash;
    _archived = w?.archived ?? false;
  }
  @override
  void dispose() { _name.dispose(); _opening.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final text = _opening.text.trim();
      final amount = Money.parseMinor(text.startsWith('-') ? text.substring(1) : text, _currency)!;
      final repo = ref.read(walletRepositoryProvider);
      if (repo == null) throw StateError('Wallet storage unavailable');
      await repo.save(Wallet(id: widget.wallet?.id, name: _name.text,
        type: _type, currency: _currency,
        openingMinor: text.startsWith('-') ? -amount : amount, archived: _archived));
      ref.invalidate(walletsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save wallet. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.wallet == null ? 'New wallet' : 'Edit wallet')),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(24), children: [
      TextFormField(controller: _name, maxLength: 80,
        decoration: const InputDecoration(labelText: 'Wallet name'),
        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null),
      const SizedBox(height: 16),
      DropdownButtonFormField<WalletType>(isExpanded: true, initialValue: _type,
        decoration: const InputDecoration(labelText: 'Wallet type'),
        items: [for (final t in WalletType.values) DropdownMenuItem(value: t, child: Text(t.label))],
        onChanged: _saving ? null : (v) => setState(() => _type = v!)),
      const SizedBox(height: 16),
      DropdownButtonFormField<AppCurrency>(isExpanded: true, key: ValueKey(_currency), initialValue: _currency,
        decoration: const InputDecoration(labelText: 'Currency'),
        items: [for (final c in AppCurrency.values) DropdownMenuItem(value: c, child: Text('${c.code} · ${c.name}'))],
        onChanged: widget.wallet != null || _saving ? null : (v) => setState(() { _currency = v!; _opening.text = '0'; })),
      const SizedBox(height: 16),
      TextFormField(controller: _opening,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: 'Opening balance (${_currency.code})',
          helperText: 'Starting balance, not income. Negative balances are allowed.'),
        validator: (v) {
          final text = (v ?? '').trim();
          return Money.parseMinor(text.startsWith('-') ? text.substring(1) : text, _currency) == null
            ? 'Enter an amount with up to ${_currency.decimalDigits} decimals' : null;
        }),
      if (widget.wallet != null) SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('Archived'), subtitle: const Text('Keeps history; prevents new entries and transfers'),
        value: _archived, onChanged: _saving ? null : (v) => setState(() => _archived = v)),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 24),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save wallet')),
    ])),
  );
}

class WalletDetailsScreen extends ConsumerWidget {
  const WalletDetailsScreen({super.key, required this.walletId});
  final int walletId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(walletsProvider);
    return data.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(appBar: AppBar(), body: _Failure(onRetry: () => ref.invalidate(walletsProvider))),
      data: (snapshot) {
        final wallet = snapshot?.wallets.where((w) => w.id == walletId).firstOrNull;
        if (wallet == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Wallet not found')));
        final txs = ref.watch(transactionsProvider);
        final entries = txs.valueOrNull?.where((t) => t.walletId == walletId).toList() ?? [];
        final transfers = snapshot!.transfers.where((t) => t.sourceId == walletId || t.destinationId == walletId);
        return Scaffold(
          appBar: AppBar(title: Text(wallet.name), actions: [
            IconButton(tooltip: 'Edit wallet', icon: const Icon(Icons.edit_outlined),
              onPressed: () => WalletsScreen._edit(context, wallet)),
          ]),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Text(Money.format(snapshot.balances[walletId]!, wallet.currency),
              style: Theme.of(context).textTheme.headlineLarge),
            Text('${wallet.currency.code} · ${wallet.type.label}${wallet.archived ? ' · Archived' : ''}'),
            Text('Available: ${Money.format(snapshot.available(walletId), wallet.currency)}'),
            Text('Reserved savings: ${Money.format(snapshot.reserved[walletId] ?? 0, wallet.currency)}'),
            const Text('Reserved savings remain part of this wallet balance.'),
            Text('Opening balance: ${Money.format(wallet.openingMinor, wallet.currency)}'),
            const SizedBox(height: 24),
            Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
            if (txs.isLoading) const LinearProgressIndicator(),
            if (txs.hasError) const Text('Could not load transactions'),
            if (entries.isEmpty && !txs.isLoading) const Text('No transactions yet'),
            for (final t in entries) ListTile(contentPadding: EdgeInsets.zero,
              title: Text(t.title), subtitle: Text('${t.occurredAt.toLocal()}'.split('.').first),
              trailing: Text(Money.format(t.signedMinor, t.currency, signed: true)),
              onTap: wallet.archived ? null : () => TransactionActions.openEditor(context, ref, existing: t)),
            const Divider(height: 40),
            Text('Debt principal movements', style: Theme.of(context).textTheme.titleLarge),
            const Text('Cash movements only · excluded from income and expenses'),
            for (final posting in snapshot.debtPostings.where((p) => p.walletId == walletId)) ListTile(
              contentPadding: EdgeInsets.zero, title: Text(posting.origin ? 'Debt principal' : 'Principal repayment'),
              subtitle: Text('${posting.reference}${posting.voided ? ' · Voided' : ''}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DebtDetailScreen(id: posting.debtId))),
              trailing: Text(Money.format(posting.voided ? 0 : posting.signedMinor, posting.currency, signed: true))),
            const Divider(height: 32),
            Text('Transfers', style: Theme.of(context).textTheme.titleLarge),
            const Text('Excluded from income and expenses. Rate: destination per 1 source.'),
            if (transfers.isEmpty) const Text('No transfers yet'),
            for (final t in transfers) ListTile(contentPadding: EdgeInsets.zero,
              title: Text('${Money.format(t.sourceMinor, t.sourceCurrency)} → ${Money.format(t.destinationMinor, t.destinationCurrency)}'),
              subtitle: Text('${snapshot.wallets.firstWhere((w) => w.id == t.sourceId).name} → ${snapshot.wallets.firstWhere((w) => w.id == t.destinationId).name}\n${t.occurredAt.toLocal()}\nRate ${t.rate}${t.note.isEmpty ? '' : '\n${t.note}'}'),
              isThreeLine: true,
              trailing: IconButton(tooltip: 'Delete transfer', icon: const Icon(Icons.delete_outline), onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Delete transfer?'), content: const Text('Both wallet balances will be reversed.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
                if (ok != true) return;
                try {
                  await ref.read(walletRepositoryProvider)!.deleteTransfer(t.id!);
                  ref.invalidate(walletsProvider);
                } catch (_) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete transfer')));
                }
              })),
          ]),
        );
      },
    );
  }
}

class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});
  @override
  ConsumerState<TransferScreen> createState() => _TransferState();
}
class _TransferState extends ConsumerState<TransferScreen> {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  int? _source, _destination;
  String? _error;
  bool _saving = false;
  @override
  void dispose() { _amount.dispose(); _rate.dispose(); _note.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(walletsProvider);
    return Scaffold(appBar: AppBar(title: const Text('Transfer money')),
      body: data.when(loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Failure(onRetry: () => ref.invalidate(walletsProvider)),
        data: (snapshot) {
          final wallets = snapshot?.wallets.where((w) => !w.archived).toList() ?? <Wallet>[];
          if (wallets.length < 2) return const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('Create at least two active wallets to transfer money.')));
          final source = wallets.where((w) => w.id == _source).firstOrNull;
          final destination = wallets.where((w) => w.id == _destination).firstOrNull;
          final same = source != null && destination != null && source.currency == destination.currency;
          String? preview;
          if (source != null && destination != null) {
            try {
              final minor = Money.parseMinor(_amount.text, source.currency);
              if (minor != null) preview = Money.format(ExchangeRate.parse(same ? '1' : _rate.text)
                  .convert(minor, source.currency, destination.currency), destination.currency);
            } catch (_) { /* Incomplete inputs are validated on submit. */ }
          }
          return ListView(padding: const EdgeInsets.all(24), children: [
            const Text('Transfer between your wallets. This is not income or spending.'),
            const SizedBox(height: 20),
            for (final isSource in [true, false]) Padding(padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<int>(isExpanded: true, key: ValueKey('${isSource ? _source : _destination}-$isSource'),
                initialValue: isSource ? source?.id : destination?.id,
                decoration: InputDecoration(labelText: isSource ? 'From wallet' : 'To wallet'),
                items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text('${w.name} (${w.currency.code})'))],
                onChanged: _saving ? null : (v) => setState(() {
                  if (isSource) { _source = v; _amount.clear(); } else { _destination = v; }
                  _rate.clear(); _error = null;
                }))),
            TextField(controller: _amount, onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Send amount ${source?.currency.code ?? ''}')),
            if (!same) TextField(controller: _rate, onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Manual exchange rate',
                helperText: '1 ${source?.currency.code ?? 'source'} = rate ${destination?.currency.code ?? 'destination'}\nNo rate is fetched or assumed. Up to 12 decimal places.', helperMaxLines: 3)),
            if (same) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Same currency · rate 1')),
            if (preview != null) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Destination receives $preview\nRounded half up to destination precision.')),
            TextField(controller: _note, maxLength: 240, decoration: const InputDecoration(labelText: 'Note (optional)')),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : () async {
              if (source == null || destination == null || source.id == destination.id) {
                setState(() => _error = 'Choose two different wallets'); return;
              }
              final minor = Money.parseMinor(_amount.text, source.currency);
              if (minor == null || minor <= 0) {
                setState(() => _error = 'Enter a valid positive source amount'); return;
              }
              setState(() { _saving = true; _error = null; });
              try {
                await ref.read(walletRepositoryProvider)!.transfer(sourceId: source.id!,
                  destinationId: destination.id!, sourceMinor: minor,
                  rate: same ? '1' : _rate.text, occurredAt: DateTime.now(), note: _note.text);
                ref.invalidate(walletsProvider);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) setState(() { _saving = false; _error = e is FormatException || e is ArgumentError
                  ? e.toString() : 'Could not save transfer. Please try again.'; });
              }
            }, child: Text(_saving ? 'Saving…' : 'Confirm transfer')),
          ]);
        }),
    );
  }
}
