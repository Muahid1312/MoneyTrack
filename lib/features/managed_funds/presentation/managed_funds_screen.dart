import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/utils/money.dart';
import '../../../core/widgets/ledger_components.dart';
import '../../../data/repositories/managed_fund_repository.dart';
import '../../documents/application/document_service.dart';
import '../application/managed_fund_providers.dart';
import '../domain/managed_fund.dart';
import 'fund_entry_screens.dart';

Future<T?> _page<T>(BuildContext context, Widget screen) =>
    Navigator.push<T>(context, MaterialPageRoute(builder: (_) => screen));

class ManagedFundsScreen extends ConsumerWidget {
  const ManagedFundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(managedFundRepositoryProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Managed Funds')),
      floatingActionButton: available
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                final id = await _page<int>(
                  context,
                  const FundMovementScreen(FundMovement.create),
                );
                if (!context.mounted || id == null) return;
                ref.invalidate(managedFundsProvider);
                await _page<void>(context, ManagedFundScreen(id));
              },
              icon: const Icon(Icons.add),
              label: const Text('New fund'),
            )
          : null,
      body: !available
          ? const Center(child: Text('Managed fund storage is unavailable.'))
          : ref
                .watch(managedFundsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) =>
                      _Retry(() => ref.invalidate(managedFundsProvider)),
                  data: (funds) => ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'پول امانتی',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.start,
                        ),
                        subtitle: Text(
                          'Track money someone gives you for a specific purpose.',
                        ),
                      ),
                      if (funds.isEmpty)
                        const ListTile(title: Text('No managed funds yet')),
                      for (final fund in funds)
                        ListTile(
                          leading: LedgerGlyph(_icon(fund.icon)),
                          title: Text(fund.name),
                          subtitle: Text(
                            '${fund.provider} · ${fund.currency.code} · ${_status(fund.status)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _page<void>(context, ManagedFundScreen(fund.id)),
                        ),
                    ],
                  ),
                ),
    );
  }
}

IconData _icon(FundIcon icon) => switch (icon) {
  FundIcon.fund => Icons.account_balance_outlined,
  FundIcon.groceries => Icons.shopping_basket_outlined,
  FundIcon.repairs => Icons.build_outlined,
  FundIcon.shopping => Icons.shopping_bag_outlined,
  FundIcon.event => Icons.event_outlined,
};

String _status(FundStatus status) => switch (status) {
  FundStatus.active => 'Active',
  FundStatus.settlementPending => 'Settlement pending',
  FundStatus.completed => 'Completed',
  FundStatus.cancelled => 'Cancelled',
};

enum _HistoryFilter {
  all('All'),
  funding('Funding'),
  purchases('Purchases'),
  reimbursements('Reimbursements');

  const _HistoryFilter(this.label);
  final String label;

  bool includes(FundEventKind kind) => switch (this) {
    all => true,
    funding =>
      kind == FundEventKind.funding || kind == FundEventKind.fundingReversal,
    purchases =>
      kind == FundEventKind.purchase ||
          kind == FundEventKind.purchaseReversal ||
          kind == FundEventKind.refund ||
          kind == FundEventKind.refundReversal,
    reimbursements =>
      kind == FundEventKind.reimburseCash ||
          kind == FundEventKind.reimburseDirect ||
          kind == FundEventKind.reimbursementReversal,
  };
}

String _eventLabel(FundEvent e) => switch (e.kind) {
  FundEventKind.funding =>
    e.target == null ? 'Funding received' : 'Corrected funding',
  FundEventKind.fundingReversal => 'Funding reversal',
  FundEventKind.purchase =>
    e.target == null ? 'Purchase' : 'Corrected purchase',
  FundEventKind.purchaseReversal => 'Purchase reversal',
  FundEventKind.refund => 'Merchant refund',
  FundEventKind.refundReversal => 'Merchant refund reversal',
  FundEventKind.reimburseDirect => 'Reimbursement from provider',
  FundEventKind.reimburseCash => 'Reimbursement from fund',
  FundEventKind.reimbursementReversal => 'Reimbursement reversal',
};

class ManagedFundScreen extends ConsumerStatefulWidget {
  const ManagedFundScreen(this.fundId, {super.key});
  final int fundId;

  @override
  ConsumerState<ManagedFundScreen> createState() => _ManagedFundState();
}

class _ManagedFundState extends ConsumerState<ManagedFundScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;
  String _query = '';

  Future<void> _enter(Widget screen) async {
    final id = await _page<int>(context, screen);
    if (!mounted || id == null) return;
    ref.invalidate(managedFundProvider(widget.fundId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managedFundProvider(widget.fundId));
    return Scaffold(
      appBar: AppBar(
        title: Text(state.valueOrNull?.ledger.fund.name ?? 'Managed fund'),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _Retry(() => ref.invalidate(managedFundProvider(widget.fundId))),
        data: (detail) => _overview(detail),
      ),
    );
  }

  Widget _overview(ManagedFundDetail detail) {
    final ledger = detail.ledger;
    final fund = ledger.fund;
    String money(int minor) => Money.format(minor, fund.currency);
    final events = ledger.events.reversed.where((event) {
      if (!_filter.includes(event.kind)) return false;
      final items = detail.items[event.id] ?? const <PurchaseLine>[];
      return [
        _eventLabel(event),
        event.party,
        event.method,
        event.note,
        for (final item in items) ...[item.name, item.category],
      ].any((text) => text.toLowerCase().contains(_query));
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        ListTile(
          leading: LedgerGlyph(_icon(fund.icon)),
          contentPadding: EdgeInsets.zero,
          title: Text(fund.provider),
          subtitle: Text(
            '${fund.currency.code} · ${_status(fund.status)}${fund.purpose.isEmpty ? '' : ' · ${fund.purpose}'}',
          ),
        ),
        if (fund.description.isNotEmpty) Text(fund.description),
        if (fund.notes.isNotEmpty) Text(fund.notes),
        if (fund.expected != null)
          Text(
            'Expected completion: ${DateFormat.yMMMd().format(fund.expected!)}',
          ),
        if (fund.status == FundStatus.active)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: () => _enter(FundPurchaseScreen(detail)),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add purchase'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _enter(
                    FundMovementScreen(FundMovement.funding, ledger: ledger),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add funds'),
                ),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                _AmountRow(
                  'Available entrusted cash',
                  money(ledger.cash),
                  primary: true,
                ),
                const Divider(),
                _AmountRow('Total received', money(ledger.received)),
                _AmountRow('Purchase expenses', money(ledger.expenses)),
                _AmountRow('Paid from entrusted cash', money(ledger.cashSpent)),
                _AmountRow('Personal advances', money(ledger.advanced)),
                _AmountRow(
                  'Reimbursed directly',
                  money(ledger.directReimbursements),
                ),
                _AmountRow(
                  'Reimbursed from fund',
                  money(ledger.fundReimbursements),
                ),
                _AmountRow(
                  'Outstanding reimbursement',
                  money(ledger.outstanding),
                ),
                _AmountRow(
                  ledger.shortfall > 0
                      ? 'Reimbursement shortfall'
                      : 'Available to return',
                  money(
                    ledger.shortfall > 0
                        ? ledger.shortfall
                        : ledger.netReturnable,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Search fund activity',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final mode in _HistoryFilter.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: _filter == mode,
                onSelected: (_) => setState(() => _filter = mode),
              ),
          ],
        ),
        if (events.isEmpty) const ListTile(title: Text('No matching records')),
        for (final event in events)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              event.kind == FundEventKind.purchase
                  ? detail.items[event.id]!.map((i) => i.name).join(', ')
                  : _eventLabel(event),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${DateFormat.yMMMd().format(event.date)} · ${ledger.reversed(event.id) ? 'Reversed' : event.method}',
            ),
            trailing: Text(money(event.total)),
            onTap: () async {
              await _page<void>(context, _FundRecordScreen(fund.id, event.id));
            },
          ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.amount, {this.primary = false});
  final String label, amount;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              amount,
              textAlign: TextAlign.end,
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FundRecordScreen extends ConsumerWidget {
  const _FundRecordScreen(this.fundId, this.eventId);
  final int fundId, eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managedFundProvider(fundId));
    final detail = state.valueOrNull;
    final ledger = detail?.ledger;
    final event = ledger?.event(eventId);
    if (detail == null || ledger == null || event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fund record')),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _Retry(() => ref.invalidate(managedFundProvider(fundId))),
      );
    }
    final writable =
        ledger.fund.status == FundStatus.active && !ledger.reversed(eventId);
    final purchase = event.kind == FundEventKind.purchase;
    final funding = event.kind == FundEventKind.funding;
    final reimbursed =
        event.kind == FundEventKind.reimburseCash ||
        event.kind == FundEventKind.reimburseDirect;
    final canCorrect = purchase && !ledger.hasPurchaseAdjustments(eventId);
    String money(int value) => Money.format(value, ledger.fund.currency);
    Future<void> enter(Widget screen) async {
      final result = await _page<int>(context, screen);
      if (context.mounted && result != null) {
        ref.invalidate(managedFundProvider(fundId));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(_eventLabel(event))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            title: Text(money(event.total)),
            subtitle: Text(
              '${DateFormat.yMMMd().add_jm().format(event.date)} · Record #$eventId',
            ),
            trailing: ledger.reversed(eventId) ? const Text('Reversed') : null,
          ),
          _AmountRow(purchase ? 'Shop' : 'Party', event.party),
          _AmountRow('Payment method', event.method),
          if (event.target != null)
            _AmountRow('Linked record', '#${event.target}'),
          if (event.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(event.note),
            ),
          if (purchase) ...[
            _AmountRow('Entrusted cash', money(event.cash)),
            _AmountRow('Personal money', money(event.personal)),
            _AmountRow(
              'Outstanding reimbursement',
              money(ledger.outstandingFor(eventId)),
            ),
            const Divider(),
            for (final item in detail.items[eventId]!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text(
                  [
                    if (item.category.isNotEmpty) item.category,
                    if (item.quantityMilli != null)
                      '${PurchaseLine.formatQuantity(item.quantityMilli!)} ${item.unit} × ${money(item.unitMinor!)}',
                  ].join(' · '),
                ),
                trailing: Text(money(item.total)),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Receipts'),
              onPressed: () => _page<void>(
                context,
                _FundReceiptsScreen(fundId, eventId, writable),
              ),
            ),
          ],
          if (writable)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (funding || canCorrect)
                  OutlinedButton(
                    onPressed: () => enter(
                      funding
                          ? FundMovementScreen(
                              FundMovement.funding,
                              ledger: ledger,
                              event: event,
                            )
                          : FundPurchaseScreen(detail, event: event),
                    ),
                    child: const Text('Correct'),
                  ),
                if (funding ||
                    canCorrect ||
                    reimbursed ||
                    event.kind == FundEventKind.refund)
                  OutlinedButton(
                    onPressed: () => enter(
                      FundMovementScreen(
                        FundMovement.reverse,
                        ledger: ledger,
                        event: event,
                      ),
                    ),
                    child: const Text('Reverse'),
                  ),
                if (purchase &&
                    (ledger.refundableCash(eventId) > 0 ||
                        ledger.outstandingFor(eventId) > 0))
                  OutlinedButton(
                    onPressed: () => enter(
                      FundMovementScreen(
                        FundMovement.refund,
                        ledger: ledger,
                        event: event,
                      ),
                    ),
                    child: const Text('Record refund'),
                  ),
                if (purchase && ledger.outstandingFor(eventId) > 0)
                  FilledButton(
                    onPressed: () => enter(
                      FundMovementScreen(
                        FundMovement.reimburse,
                        ledger: ledger,
                        event: event,
                      ),
                    ),
                    child: const Text('Reimburse advance'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FundReceiptsScreen extends ConsumerStatefulWidget {
  const _FundReceiptsScreen(this.fund, this.purchase, this.editable);
  final int fund, purchase;
  final bool editable;

  @override
  ConsumerState<_FundReceiptsScreen> createState() => _FundReceiptsState();
}

class _FundReceiptsState extends ConsumerState<_FundReceiptsScreen> {
  late Future<List<ManagedReceipt>> _items;
  bool _busy = false;
  String? _message;

  ManagedFundRepository get _repo => ref.read(managedFundRepositoryProvider)!;
  Future<List<ManagedReceipt>> _load() =>
      _repo.receipts(widget.fund, widget.purchase);

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<void> _perform(Future<void> Function() change) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await change();
      if (mounted) setState(() => _items = _load());
    } on FundRule catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) {
        setState(() => _message = 'Could not open or save this receipt photo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(String kind, {int? replace}) => _perform(() async {
    final photo = await DocumentBridge.pick(kind, compressPhoto: true);
    if (!mounted || photo == null) return;
    final name = photo.name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    await _repo.saveReceipt(
      widget.fund,
      widget.purchase,
      name: name.isEmpty
          ? 'Receipt photo'
          : name.length > 120
          ? name.substring(0, 120)
          : name,
      bytes: photo.bytes,
      replace: replace,
    );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase receipts')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (widget.editable)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick('camera'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick('gallery'),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Gallery'),
              ),
            ],
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!)),
        FutureBuilder<List<ManagedReceipt>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Retry(() => setState(() => _items = _load()));
            }
            final receipts = snapshot.data;
            if (receipts == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (receipts.isEmpty) {
              return const ListTile(title: Text('No receipts yet'));
            }
            return Column(
              children: [
                for (final receipt in receipts)
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(receipt.name),
                    onTap: _busy
                        ? null
                        : () => _perform(() async {
                            final bytes = await _repo.receipt(
                              widget.fund,
                              widget.purchase,
                              receipt.id,
                            );
                            if (!context.mounted) return;
                            await _page<void>(
                              context,
                              Scaffold(
                                appBar: AppBar(title: Text(receipt.name)),
                                body: Center(
                                  child: InteractiveViewer(
                                    child: Image.memory(bytes),
                                  ),
                                ),
                              ),
                            );
                          }),
                    trailing: widget.editable
                        ? PopupMenuButton<String>(
                            tooltip: 'Receipt options',
                            enabled: !_busy,
                            onSelected: (action) async {
                              if (action != 'remove') {
                                await _pick(action, replace: receipt.id);
                                return;
                              }
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('Remove this receipt?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                await _perform(
                                  () => _repo.removeReceipt(
                                    widget.fund,
                                    widget.purchase,
                                    receipt.id,
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'camera',
                                child: Text('Replace with camera'),
                              ),
                              PopupMenuItem(
                                value: 'gallery',
                                child: Text('Replace from gallery'),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove receipt'),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry(this.retry);
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: retry,
      child: const Text('Retry loading records'),
    ),
  );
}
