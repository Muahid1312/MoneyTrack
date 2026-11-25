import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/repositories/managed_fund_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../settings/application/settings_controller.dart';
import '../application/managed_fund_providers.dart';
import '../domain/managed_fund.dart';
import 'fund_form_widgets.dart';

enum FundMovement { create, funding, refund, reimburse, reverse }

class FundMovementScreen extends ConsumerStatefulWidget {
  const FundMovementScreen(this.action, {super.key, this.ledger, this.event});
  final FundMovement action;
  final ManagedLedger? ledger;
  final FundEvent? event;

  @override
  ConsumerState<FundMovementScreen> createState() => _FundMovementState();
}

class _FundMovementState extends ConsumerState<FundMovementScreen> {
  final _key = managedRequestKey();
  final _inputs = FundFields();
  late AppCurrency _currency;
  late DateTime _date;
  DateTime? _expected;
  FundIcon _icon = FundIcon.fund;
  bool _fromFund = false;

  ManagedFund? get _fund => widget.ledger?.fund;
  FundEvent? get _event => widget.event;

  @override
  void initState() {
    super.initState();
    _currency = _fund?.currency ?? ref.read(currencyProvider);
    _date = widget.action == FundMovement.funding && _event != null
        ? _event!.date
        : ref.read(clockProvider)();
  }

  @override
  void dispose() {
    _inputs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final event = _event;
    final creating = action == FundMovement.create;
    final title = switch (action) {
      FundMovement.create => 'New managed fund',
      FundMovement.funding => event == null ? 'Add funds' : 'Correct funding',
      FundMovement.refund => 'Merchant refund',
      FundMovement.reimburse => 'Record reimbursement',
      FundMovement.reverse => 'Reverse record',
    };
    final amountLabel = creating ? 'Initial received amount' : 'Amount';
    final provider = _fund?.provider ?? '';
    String money(int amount) => Money.format(amount, _currency);
    return FundForm(
      title: title,
      button: creating
          ? 'Create fund'
          : action == FundMovement.reverse
          ? 'Reverse record'
          : 'Save record',
      children: [
        if (creating) ...[
          _field('Fund name', 120),
          _field('Provider', 120),
          DropdownButtonFormField<AppCurrency>(
            isExpanded: true,
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final c in AppCurrency.values)
                DropdownMenuItem(value: c, child: Text(c.code)),
            ],
            onChanged: (value) => setState(() => _currency = value!),
          ),
          const SizedBox(height: 12),
        ],
        if (action == FundMovement.funding)
          _field('Provider', 120, event?.party ?? provider),
        if (action == FundMovement.funding || creating)
          FundInput(
            '$amountLabel (${_currency.code})',
            _inputs.field(
              'amount',
              event == null ? '' : Money.plain(event.total, _currency),
            ),
            number: true,
          ),
        if (action == FundMovement.refund) ...[
          Text(
            'Refund to entrusted cash up to ${money(widget.ledger!.refundableCash(event!.id))}.',
          ),
          FundInput(
            'Refund into fund',
            _inputs.field('cash', '0'),
            number: true,
          ),
          Text(
            'Refund to personal money up to ${money(widget.ledger!.outstandingFor(event.id))}.',
          ),
          FundInput(
            'Refund to you',
            _inputs.field('personal', '0'),
            number: true,
          ),
          _field('Merchant', 120, event.party == 'Purchase' ? '' : event.party),
        ],
        if (action == FundMovement.reimburse) ...[
          Text(
            'Outstanding for this purchase: ${money(widget.ledger!.outstandingFor(event!.id))}',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            isExpanded: true,
            initialValue: _fromFund,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: const [
              DropdownMenuItem(
                value: false,
                child: Text('Direct from provider'),
              ),
              DropdownMenuItem(value: true, child: Text('Entrusted cash')),
            ],
            onChanged: (v) => setState(() => _fromFund = v!),
          ),
          const SizedBox(height: 12),
          FundInput(
            'Amount (${_currency.code})',
            _inputs.field('amount'),
            number: true,
          ),
          _field('Provider', 120, provider),
        ],
        if (action == FundMovement.reverse)
          Text(
            'A reversing entry will offset record #${event!.id} for ${money(event.total)}.',
          ),
        if (action != FundMovement.reverse)
          _field(
            'Payment method',
            80,
            action == FundMovement.funding ? event?.method ?? 'Cash' : 'Cash',
          ),
        FundDateField(
          value: _date,
          onChange: (value) => setState(() => _date = value),
        ),
        if (creating)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Optional fund details'),
            children: [
              _field('Purpose', 120),
              _field('Description', 1000),
              FundDateField(
                label: 'Expected completion date',
                value: _expected,
                includeTime: false,
                onChange: (value) => setState(() => _expected = value),
              ),
              if (_expected != null)
                TextButton(
                  onPressed: () => setState(() => _expected = null),
                  child: const Text('Clear expected date'),
                ),
              _field('Notes', 1000),
              DropdownButtonFormField<FundIcon>(
                isExpanded: true,
                initialValue: _icon,
                decoration: const InputDecoration(labelText: 'Fund icon'),
                items: [
                  for (final icon in FundIcon.values)
                    DropdownMenuItem(value: icon, child: Text(icon.name)),
                ],
                onChanged: (v) => setState(() => _icon = v!),
              ),
            ],
          ),
        if (action == FundMovement.reverse)
          _field('Reason for reversal', 1000)
        else
          _field(creating ? 'Funding note' : 'Note', 1000, event?.note ?? ''),
      ],
      submit: () {
        final repo = ref.read(managedFundRepositoryProvider)!;
        final method = _inputs.value('Payment method');
        final note = _inputs.value('Note');
        int amount(String key, {bool zero = false}) =>
            fundAmount(_inputs.value(key), _currency, zeroAllowed: zero);
        return switch (action) {
          FundMovement.create => repo.create(
            key: _key,
            name: _inputs.value('Fund name'),
            provider: _inputs.value('Provider'),
            currency: _currency,
            initialMinor: amount('amount'),
            date: _date,
            method: method,
            purpose: _inputs.value('Purpose'),
            description: _inputs.value('Description'),
            notes: _inputs.value('Notes'),
            expected: _expected,
            icon: _icon,
            fundingNote: _inputs.value('Funding note'),
          ),
          FundMovement.funding => repo.funding(
            _fund!.id,
            key: _key,
            amount: amount('amount'),
            provider: _inputs.value('Provider'),
            date: _date,
            method: method,
            note: note,
            correct: event?.id,
          ),
          FundMovement.refund => repo.refund(
            _fund!.id,
            key: _key,
            purchase: event!.id,
            cash: amount('cash', zero: true),
            personal: amount('personal', zero: true),
            date: _date,
            merchant: _inputs.value('Merchant'),
            method: method,
            note: note,
          ),
          FundMovement.reimburse => repo.reimburse(
            _fund!.id,
            key: _key,
            purchase: event!.id,
            amount: amount('amount'),
            fromFund: _fromFund,
            date: _date,
            provider: _inputs.value('Provider'),
            method: method,
            note: note,
          ),
          FundMovement.reverse => repo.reverse(
            _fund!.id,
            key: _key,
            target: event!.id,
            date: _date,
            reason: _inputs.value('Reason for reversal'),
          ),
        };
      },
    );
  }

  Widget _field(String label, int max, [String prefill = '']) =>
      FundInput(label, _inputs.field(label, prefill), maxLength: max);
}

enum _PaymentSplit {
  cash('Entrusted cash'),
  personal('Personal money'),
  mixed('Both sources');

  const _PaymentSplit(this.label);
  final String label;
}

class _LineEditor {
  _LineEditor(AppCurrency currency, [PurchaseLine? item])
    : name = TextEditingController(text: item?.name),
      category = TextEditingController(text: item?.category),
      quantity = TextEditingController(
        text: item?.quantityMilli == null
            ? ''
            : PurchaseLine.formatQuantity(item!.quantityMilli!),
      ),
      unit = TextEditingController(text: item?.unit),
      unitPrice = TextEditingController(
        text: item?.unitMinor == null
            ? ''
            : Money.plain(item!.unitMinor!, currency),
      ),
      total = TextEditingController(
        text: item == null ? '' : Money.plain(item.total, currency),
      ),
      itemized = item?.quantityMilli != null;

  final TextEditingController name, category, quantity, unit, unitPrice, total;
  bool itemized;

  PurchaseLine read(AppCurrency currency) {
    final qty = itemized
        ? PurchaseLine.parseQuantity(normalizeFundDigits(quantity.text))
        : null;
    requireManaged(
      !itemized || qty != null,
      'Enter a quantity with up to three decimal places.',
    );
    return PurchaseLine(
      name: name.text,
      category: category.text,
      quantityMilli: qty,
      unit: itemized ? unit.text : '',
      unitMinor: itemized ? fundAmount(unitPrice.text, currency) : null,
      totalMinor: itemized ? null : fundAmount(total.text, currency),
    );
  }

  void dispose() {
    for (final field in [name, category, quantity, unit, unitPrice, total]) {
      field.dispose();
    }
  }
}

class FundPurchaseScreen extends ConsumerStatefulWidget {
  const FundPurchaseScreen(this.detail, {super.key, this.event});
  final ManagedFundDetail detail;
  final FundEvent? event;

  @override
  ConsumerState<FundPurchaseScreen> createState() => _FundPurchaseState();
}

class _FundPurchaseState extends ConsumerState<FundPurchaseScreen> {
  final _key = managedRequestKey();
  final _inputs = FundFields();
  late DateTime _date;
  late _PaymentSplit _split;
  late final List<_LineEditor> _items;

  AppCurrency get _currency => widget.detail.ledger.fund.currency;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _date = event?.date ?? ref.read(clockProvider)();
    _split = event == null || event.personal == 0
        ? _PaymentSplit.cash
        : event.cash == 0
        ? _PaymentSplit.personal
        : _PaymentSplit.mixed;
    _items = event == null
        ? [_LineEditor(_currency)]
        : [
            for (final item in widget.detail.items[event.id]!)
              _LineEditor(_currency, item),
          ];
  }

  @override
  void dispose() {
    _inputs.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final cash = widget.detail.ledger.cash + (event?.cash ?? 0);
    final code = _currency.code;
    return FundForm(
      title: event == null ? 'Add purchase' : 'Correct purchase',
      button: 'Save purchase',
      children: [
        for (var i = 0; i < _items.length; i++) _line(i, _items[i]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _items.length == 100
                ? null
                : () => setState(() => _items.add(_LineEditor(_currency))),
            icon: const Icon(Icons.add),
            label: const Text('Add another item'),
          ),
        ),
        DropdownButtonFormField<_PaymentSplit>(
          isExpanded: true,
          initialValue: _split,
          decoration: const InputDecoration(labelText: 'Payment source'),
          items: [
            for (final s in _PaymentSplit.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged: (s) => setState(() => _split = s!),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Entrusted cash available'),
          trailing: Text(Money.format(cash, _currency)),
        ),
        if (_split == _PaymentSplit.mixed)
          FundInput(
            'Amount from entrusted cash ($code)',
            _inputs.field(
              'cash',
              event == null ? '' : Money.plain(event.cash, _currency),
            ),
            number: true,
          ),
        FundInput(
          'Payment method',
          _inputs.field('method', event?.method ?? 'Cash'),
          maxLength: 80,
        ),
        FundDateField(
          value: _date,
          onChange: (value) => setState(() => _date = value),
        ),
        FundInput(
          'Shop (optional)',
          _inputs.field(
            'shop',
            event?.party == 'Purchase' ? '' : event?.party ?? '',
          ),
          maxLength: 120,
        ),
        FundInput(
          'Note (optional)',
          _inputs.field('note', event?.note ?? ''),
          maxLength: 1000,
        ),
      ],
      submit: () {
        final lines = _items.map((item) => item.read(_currency)).toList();
        final total = lines.fold(0, (sum, line) => sum + line.total);
        final cash = switch (_split) {
          _PaymentSplit.cash => total,
          _PaymentSplit.personal => 0,
          _PaymentSplit.mixed => fundAmount(_inputs.value('cash'), _currency),
        };
        requireManaged(
          _split != _PaymentSplit.mixed || cash < total,
          'The mixed payment needs a positive amount from both sources.',
        );
        return ref
            .read(managedFundRepositoryProvider)!
            .purchase(
              widget.detail.ledger.fund.id,
              key: _key,
              items: lines,
              cash: cash,
              date: _date,
              method: _inputs.value('method'),
              shop: _inputs.value('shop'),
              note: _inputs.value('note'),
              correct: event?.id,
            );
      },
    );
  }

  Widget _line(int index, _LineEditor item) => Column(
    key: ObjectKey(item),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_items.length > 1)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Item ${index + 1}'),
          trailing: IconButton(
            tooltip: 'Remove item ${index + 1}',
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() => _items.removeAt(index));
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => item.dispose(),
              );
            },
          ),
        ),
      FundInput('Product or expense name', item.name, maxLength: 120),
      if (item.itemized) ...[
        FundInput('Quantity', item.quantity, number: true),
        FundInput('Unit (for example, kg)', item.unit, maxLength: 40),
        FundInput(
          'Unit price (${_currency.code})',
          item.unitPrice,
          number: true,
        ),
        ListenableBuilder(
          listenable: Listenable.merge([item.quantity, item.unitPrice]),
          builder: (context, _) {
            final quantity = PurchaseLine.parseQuantity(
              normalizeFundDigits(item.quantity.text),
            );
            final price = Money.parseMinor(
              normalizeFundDigits(item.unitPrice.text),
              _currency,
            );
            if (quantity == null || price == null || price == 0) {
              return const SizedBox.shrink();
            }
            try {
              final total = PurchaseLine(
                name: 'Item',
                quantityMilli: quantity,
                unit: 'unit',
                unitMinor: price,
              ).total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Item total: ${Money.format(total, _currency)}'),
              );
            } on FundRule {
              return const SizedBox.shrink();
            }
          },
        ),
      ] else
        FundInput('Total amount (${_currency.code})', item.total, number: true),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use quantity and unit price'),
        value: item.itemized,
        onChanged: (enabled) => setState(() => item.itemized = enabled),
      ),
      FundInput('Category (optional)', item.category, maxLength: 120),
      const Divider(),
    ],
  );
}
