import '../../../core/utils/app_language.dart';
import '../../../core/widgets/finance_hero.dart';
import '../../../core/utils/amount_input.dart';
import '../../../core/theme/app_typography.dart';
import '../../transactions/presentation/widgets/amount_keypad.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/ledger_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
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
      appBar: AppBar(title: Text(context.tr('Accounts', 'حساب‌ها')), actions: [
        IconButton(tooltip: 'Transfer money', icon: const Icon(Icons.swap_horiz),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const TransferScreen()))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context), icon: const Icon(Icons.add),
        label: Text(context.tr('New wallet', 'حساب جدید'))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Failure(onRetry: () => ref.invalidate(walletsProvider)),
        data: (snapshot) {
          if (snapshot == null) return const Center(child: Text('Wallet storage is unavailable'));
          final currencies=ref.watch(currencyBalancesProvider);
          return ListView(padding:const EdgeInsets.fromLTRB(12,8,12,88),children:[
            if(snapshot.wallets.isEmpty)const ListTile(title:Text('Create your first wallet to start tracking.')),
            for(final e in currencies.entries) ...[
              Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('${e.key.name} · ${e.key.code}',style:Theme.of(context).textTheme.titleMedium)),
              FinanceHero(label: 'Total personal balance · ${e.key.code}', amount: Money.format(e.value,e.key), details: [
                (label:'Reserved',value:Money.format(snapshot.wallets.where((w)=>w.currency==e.key).fold<int>(0,(n,w)=>n+(snapshot.reserved[w.id]??0)),e.key)),
                (label:'Available',value:Money.format(snapshot.wallets.where((w)=>w.currency==e.key).fold<int>(0,(n,w)=>n+snapshot.available(w.id!)),e.key))
              ]),
              const SizedBox(height: 8),
              for(final w in snapshot.wallets.where((w)=>w.currency==e.key))
                _AccountRow(wallet:w,snapshot:snapshot),
            ]
          ]);
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, [Wallet? wallet]) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WalletEditorScreen(wallet: wallet)));
}

class _AccountRow extends StatelessWidget{
  const _AccountRow({required this.wallet,required this.snapshot});
  final Wallet wallet;final WalletSnapshot snapshot;
  @override Widget build(BuildContext context){
    final w=wallet,c=w.currency,id=w.id!,reserved=snapshot.reserved[w.id]??0;
    final t = Theme.of(context).textTheme;
    final narrow = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final identity = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(w.name, style: t.titleMedium),
      Text('${w.type.label} · ${c.code}${w.archived ? " · Archived" : ""}', style: t.bodySmall),
    ]);
    final amount = Column(crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
      Text(Money.format(snapshot.available(id),c), style: t.titleSmall),
      Text(context.tr('Available', 'قابل مصرف'), style: t.labelSmall),
    ]);
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => WalletDetailsScreen(walletId: id))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
          LedgerGlyph(w.archived ? Icons.archive_outlined : Icons.account_balance_wallet_outlined),
          const SizedBox(width: 10),
          Expanded(child: narrow ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            identity, const SizedBox(height: 4), amount,
          ]) : Row(children: [Expanded(child: identity), const SizedBox(width: 8), Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: amount))])),
        ])),
        if (reserved != 0) Padding(padding: const EdgeInsets.fromLTRB(12,0,12,8), child: Align(alignment: AlignmentDirectional.centerEnd,
          child: Text('Cash ${Money.format(snapshot.balances[id]!,c)} · Reserved ${Money.format(reserved,c)}', style: t.bodySmall))),
      ]),
    ));
  }
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
    _currency = w?.currency ?? ref.read(walletsProvider).valueOrNull?.wallets.firstOrNull?.currency ?? AppCurrency.afn;
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
            IconButton(
              tooltip: 'Reconcile balance', icon: const Icon(Icons.calculate_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context, isScrollControlled: true, useSafeArea: true,
                builder: (_) => _CountWalletSheet(wallet, snapshot.balances[walletId]!),
              ),
            ),
            IconButton(tooltip: 'Edit wallet', icon: const Icon(Icons.edit_outlined),
              onPressed: () => WalletsScreen._edit(context, wallet)),
          ]),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            FinanceHero(
              label: '${wallet.currency.code} · ${wallet.type.label}${wallet.archived ? ' · Archived' : ''}',
              amount: Money.format(snapshot.balances[walletId]!, wallet.currency),
              details: [
                (label: context.tr('Available', 'قابل مصرف'), value: Money.format(snapshot.available(walletId), wallet.currency)),
                (label: context.tr('Reserved savings', 'پس‌انداز محفوظ'), value: Money.format(snapshot.reserved[walletId] ?? 0, wallet.currency)),
              ],
            ),
            const SizedBox(height: 12),
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
  const TransferScreen({super.key,this.initialDate,this.sourceId,this.onPosted});
  final DateTime? initialDate;
  final int? sourceId;
  final void Function(DateTime,AppCurrency)? onPosted;
  @override
  ConsumerState<TransferScreen> createState() => _TransferState();
}
class _TransferState extends ConsumerState<TransferScreen> {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  int? _source, _destination;
  late DateTime _date;
  @override
  void initState(){super.initState();_source=widget.sourceId??ref.read(selectedWalletProvider)?.id;_date=widget.initialDate??DateTime.now();}
  String? _error;
  bool _saving = false;
  @override
  void dispose() { _amount.dispose(); _rate.dispose(); _note.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(walletsProvider);
    return Scaffold(appBar: AppBar(title: Text(context.tr('Transfer money', 'انتقال پول'))),
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
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [
            ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.calendar_today_outlined),title:Text(MaterialLocalizations.of(context).formatMediumDate(_date)),subtitle:const Text('Transfer date'),onTap:_saving?null:()async{
              final picked=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(_date.year<2000?_date.year:2000),lastDate:DateTime.now());
              if(picked!=null && mounted)setState(()=>_date=DateTime(picked.year,picked.month,picked.day,_date.hour,_date.minute));
            }),
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
            TextField(controller: _amount, enabled: !_saving, onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.none,
              style: AppTypography.amount(30), textAlign: TextAlign.center,
              decoration: InputDecoration(labelText: 'Send amount ${source?.currency.code ?? ''}')),
            if (!same) TextField(controller: _rate, onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Manual exchange rate',
                helperText: '1 ${source?.currency.code ?? 'source'} = rate ${destination?.currency.code ?? 'destination'}\nNo rate is fetched or assumed. Up to 12 decimal places.', helperMaxLines: 3)),
            if (same) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Same currency · rate 1')),
            if (preview != null) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Destination receives $preview\nRounded half up to destination precision.')),
            if (source != null) ...[
              const SizedBox(height: 10),
              AmountKeypad(
                allowDecimal: source.currency.decimalDigits > 0, enabled: !_saving,
                onKey: (key) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    final raw = _amount.text.trim();
                    final next = applyAmountKey(AmountInput(
                      Money.parseMinor(raw, source.currency) == null ? raw : raw.replaceAll(',', ''),
                      source.currency,
                    ), key);
                    _amount.text = next.isEmpty ? '' : next.display;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: _note, maxLength: 240, decoration: const InputDecoration(labelText: 'Note (optional)')),
            ])),
            SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_error != null) Semantics(liveRegion: true, child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
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
                  rate: same ? '1' : _rate.text, occurredAt: _date, note: _note.text);
                if(!context.mounted)return;
                widget.onPosted?.call(_date,source.currency);
                ref.invalidate(walletsProvider);
                if (context.mounted) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Transfer saved')));Navigator.pop(context,true);}
              } catch (e) {
                if (mounted) setState(() { _saving = false; _error = e is FormatException || e is ArgumentError
                  ? e.toString() : 'Could not save transfer. Please try again.'; });
              }
            }, child: Text(_saving ? 'Saving…' : context.tr('Confirm transfer', 'تأیید انتقال'))),
              ]),
            ),
          ]);
        }),
    );
  }
}


class _CountWalletSheet extends StatefulWidget {
  const _CountWalletSheet(this.wallet, this.recorded);
  final Wallet wallet;
  final int recorded;

  @override
  State<_CountWalletSheet> createState() => _CountWalletSheetState();
}

class _CountWalletSheetState extends State<_CountWalletSheet> {
  final _counted = TextEditingController();
  int? _compared;
  bool _invalid = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  void _compare() {
    final raw = _counted.text.trim();
    final negative = raw.startsWith('-');
    final minor = Money.parseMinor(negative ? raw.substring(1) : raw, widget.wallet.currency);
    setState(() {
      _invalid = minor == null;
      _compared = minor == null ? null : negative ? -minor : minor;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.wallet.currency;
    final difference = _compared == null ? null : _compared! - widget.recorded;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Reconcile balance', style: t.titleLarge),
          const SizedBox(height: 8),
          Text('${widget.wallet.name} · ${currency.code}'),
          Text('Recorded cash: ${Money.format(widget.recorded, currency)}'),
          const SizedBox(height: 14),
          TextField(
            controller: _counted,
            keyboardType: TextInputType.numberWithOptions(decimal: currency.decimalDigits > 0, signed: true),
            decoration: InputDecoration(
              labelText: 'Counted balance (${currency.code})',
              errorText: _invalid ? 'Enter a valid balance.' : null,
            ),
            onChanged: (_) => setState(() { _compared = null; _invalid = false; }),
            onSubmitted: (_) => _compare(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _compare, child: const Text('Compare')),
          if (difference != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(difference == 0 ? 'Balances match' :
              'Difference: ${Money.format(difference, currency, signed: true)}', style: t.titleMedium)),
            if (difference != 0)
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Review wallet history')),
          ],
        ]),
      ),
    );
  }
}
