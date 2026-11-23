import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../data/storage/portable_snapshot.dart';
import '../../documents/application/document_service.dart';
import '../../settings/application/settings_controller.dart';
import '../application/group_providers.dart';
import '../domain/group_fund.dart';

enum TripFormMode { create, member, contribution, expense, payment, action }

class TripForm extends ConsumerStatefulWidget {
  const TripForm(
    this.mode, {
    super.key,
    this.group,
    this.member,
    this.kind,
    this.related,
    this.original,
    this.initialAmount,
    this.title,
    this.plan = const {},
  });
  final TripFormMode mode;
  final GroupFund? group;
  final int? member, related, original, initialAmount;
  final EntryKind? kind;
  final String? title;
  final Map<int, int> plan;
  @override
  ConsumerState<TripForm> createState() => _TripFormState();
}

class _TripFormState extends ConsumerState<TripForm> {
  final fields = <String, TextEditingController>{};
  final requestKey = groupRequestKey();
  late DateTime date;
  late AppCurrency currency;
  late EntryKind kind;
  int? member;
  String method = 'Cash', category = 'Food';
  String? error;
  Uint8List? image;
  bool busy = false, advanced = false;
  GroupFund? get g => widget.group;
  TripEntry? get old => g?.events[widget.original];
  TripFormMode get mode => widget.mode;
  static const categories = [
    'Transportation',
    'Food',
    'Drinks',
    'Fruits',
    'Snacks',
    'Tickets',
    'Accommodation',
    'Equipment',
    'Other',
  ];
  static const custom = 'Enter a category…';
  TextEditingController field(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  String value(String key) => field(key).text.trim();
  @override
  void initState() {
    super.initState();
    currency = g?.currency ?? ref.read(currencyProvider);
    kind =
        old?.kind ??
        widget.kind ??
        (mode == TripFormMode.expense
            ? EntryKind.cashExpense
            : EntryKind.contribution);
    member = widget.member ?? old?.member ?? g?.roster.firstOrNull?.id;
    date = old?.at ?? DateTime.now();
    if (widget.initialAmount != null || old != null) {
      field('Amount').text = Money.plain(
        old?.amount ?? widget.initialAmount!,
        currency,
      );
    }
    if (mode == TripFormMode.contribution && old == null) {
      suggestContribution();
    }
    if (mode == TripFormMode.member) {
      final m = g!.members[widget.member];
      field('Member name').text = m?.name ?? '';
      field('Expected contribution').text = Money.plain(
        m?.expected ?? g!.project['expected_minor'] as int,
        currency,
      );
    }
    if (old != null) {
      final e = old!;
      field('Note').text = e.note;
      field('Item').text = e.label;
      method = e.method.isEmpty ? 'Cash' : e.method;
      category = e.category;
      if (e.quantity != null) {
        field('Quantity').text = quantityText(e.quantity!);
        field('Unit price').text = Money.plain(e.unit!, currency);
        advanced = true;
      }
    }
  }

  void suggestContribution() {
    final due = g!.memberDue(g!.members[member]!);
    field('Amount').text = due > 0 ? Money.plain(due, currency) : '';
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? amount(String key, {bool optional = false}) {
    final v = value(key);
    if (optional && v.isEmpty) return null;
    final n = Money.parseMinor(v, currency);
    requireFund(n != null, 'Enter a valid $key in ${currency.code}.');
    return n;
  }

  String get title =>
      widget.title ??
      switch (mode) {
        TripFormMode.create => 'New group',
        TripFormMode.member =>
          widget.member == null ? 'Add member' : 'Edit member',
        TripFormMode.contribution =>
          old == null ? 'Add contribution' : 'Correct contribution',
        TripFormMode.expense => old == null ? 'Add expense' : 'Correct expense',
        TripFormMode.payment => kind.label,
        TripFormMode.action => kind.label,
      };
  Widget input(
    String label, {
    String? hint,
    bool number = false,
    int lines = 1,
    bool readOnly = false,
    VoidCallback? change,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(label),
      controller: field(label),
      enabled: !busy,
      readOnly: readOnly,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: number && label != 'Quantity' ? currency.code : null,
      ),
      onChanged: change == null ? null : (_) => change(),
    ),
  );
  Widget choice<T>(
    String label,
    T current,
    Map<T, String> options,
    ValueChanged<T> set,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$current'),
      isExpanded: true,
      initialValue: current,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options.entries)
          DropdownMenuItem(
            value: o.key,
            child: Text(o.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: busy
          ? null
          : (v) {
              if (v != null) setState(() => set(v));
            },
    ),
  );
  Widget dateRow({bool time = true}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.event_outlined),
    title: Text(Dates.shortDate(date)),
    subtitle: time ? Text(TimeOfDay.fromDateTime(date).format(context)) : null,
    trailing: const Icon(Icons.edit_calendar_outlined),
    onTap: busy
        ? null
        : () async {
            final day = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (day == null || !mounted) return;
            final clock = time
                ? await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(date),
                  )
                : null;
            if (mounted && (!time || clock != null)) {
              setState(
                () => date = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  clock?.hour ?? 0,
                  clock?.minute ?? 0,
                ),
              );
            }
          },
  );
  Future<void> pickPhoto(String source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final doc = await DocumentBridge.pick(source);
      if (doc == null || !mounted) return;
      var bytes = doc.bytes;
      if (bytes.length > 1024 * 1024) {
        requireFund(
          (await PortableSnapshot.validateContent(bytes)).startsWith('image/'),
          'Choose a photo.',
        );
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            var size = 960;
            while (bytes.length > 1024 * 1024) {
              final codec = await descriptor.instantiateCodec(
                targetWidth: descriptor.width >= descriptor.height
                    ? size
                    : null,
                targetHeight: descriptor.height > descriptor.width
                    ? size
                    : null,
              );
              try {
                final frame = await codec.getNextFrame();
                try {
                  final data = await frame.image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (data == null) {
                    throw const FundError('Could not read the photo.');
                  }
                  bytes = data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  );
                } finally {
                  frame.image.dispose();
                }
              } finally {
                codec.dispose();
              }
              size ~/= 2;
            }
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
      }
      await GroupRepository.validateImage(bytes);
      if (mounted) {
        setState(() {
          image = bytes;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not read that photo. Choose a JPEG or PNG.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget photo(String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      if (image != null) Image.memory(image!, height: 80),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy ? null : () => pickPhoto('gallery'),
            icon: const Icon(Icons.photo_outlined),
            label: const Text('Gallery'),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => pickPhoto('camera'),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Camera'),
          ),
        ],
      ),
    ],
  );
  void calculate() {
    final q = Money.parseMinor(value('Quantity'), AppCurrency.kwd),
        u = Money.parseMinor(value('Unit price'), currency);
    setState(() {
      if (q != null && u != null) {
        try {
          field('Amount').text = Money.plain(quantityCost(q, u), currency);
          error = null;
        } on FundError catch (e) {
          error = e.message;
        }
      }
    });
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(groupRepositoryProvider);
      requireFund(repo != null, 'Group storage is unavailable.');
      int? newId;
      switch (mode) {
        case TripFormMode.create:
          newId = await repo!.create(
            key: requestKey,
            name: value('Group name'),
            currency: currency,
            date: date,
            members: value('Members')
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            expected: amount('Expected per member', optional: true) ?? 0,
            budget: amount('Expected budget', optional: true),
            description: value('Description'),
            location: value('Location'),
            image: image,
          );
        case TripFormMode.member:
          await repo!.member(
            g!.id,
            id: widget.member,
            name: value('Member name'),
            expected: amount('Expected contribution', optional: true) ?? 0,
          );
        default:
          final money = mode != TripFormMode.action;
          final q = value('Quantity').isEmpty
              ? null
              : Money.parseMinor(value('Quantity'), AppCurrency.kwd);
          final unit = amount('Unit price', optional: true);
          requireFund(
            value('Quantity').isEmpty || q != null,
            'Enter a quantity with up to three decimal places.',
          );
          requireFund(
            (q == null) == (unit == null),
            'Enter both quantity and unit price.',
          );
          final e = TripEntry(
            kind: kind,
            at: date,
            amount: money
                ? (q != null ? quantityCost(q, unit!) : amount('Amount')!)
                : 0,
            member: mode == TripFormMode.action || kind == EntryKind.cashCount
                ? null
                : kind == EntryKind.liability
                ? null
                : kind == EntryKind.payBill
                ? g!.events[widget.related]?.member
                : member,
            related: widget.related,
            label: value('Item'),
            category: kind.purchase
                ? (category == custom ? value('Custom category') : category)
                : '',
            method: kind == EntryKind.contribution ? method : '',
            note: value('Note'),
            quantity: q,
            unit: unit,
            allocation: widget.plan,
          );
          final replacing = widget.original != null;
          final first = replacing
              ? TripEntry(
                  kind: EntryKind.reverse,
                  related: widget.original,
                  note: value('Reason for correction'),
                  at: DateTime.now(),
                )
              : e;
          await repo!.post(
            g!.id,
            requestKey,
            first,
            revision: g!.revision,
            image: image,
            replacement: replacing ? e : null,
          );
      }
      if (!mounted) return;
      ref.invalidate(groupsProvider);
      if (g != null) ref.invalidate(groupProvider(g!.id));
      Navigator.pop(context, newId ?? g?.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FundError
              ? e.message
              : 'Could not save. Reopen this form to check the latest records.';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <String>{
      ...categories,
      if (g != null)
        ...g!.events.values
            .where((e) => e.kind.purchase)
            .map((e) => e.category),
      custom,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (mode == TripFormMode.create) ...[
                    input('Group name', hint: 'Paghman trip'),
                    input('Members', hint: 'One name per line', lines: 4),
                    choice('Currency', currency, {
                      for (final c in AppCurrency.values) c: c.code,
                    }, (v) => currency = v),
                    dateRow(time: false),
                    input('Expected per member', number: true),
                    ExpansionTile(
                      title: const Text('More details'),
                      children: [
                        input('Location'),
                        input('Description'),
                        input('Expected budget', number: true),
                        photo('Group photo'),
                      ],
                    ),
                  ] else if (mode == TripFormMode.member) ...[
                    input('Member name'),
                    input('Expected contribution', number: true),
                  ] else if (mode == TripFormMode.action) ...[
                    if (kind == EntryKind.confirm) ...[
                      Text(
                        'Confirm these allocations. Record each payment when the member receives it.',
                      ),
                      for (final m in g!.roster)
                        ListTile(
                          title: Text(m.name),
                          trailing: Text(
                            Money.format(widget.plan[m.id] ?? 0, currency),
                          ),
                        ),
                    ],
                    if (kind == EntryKind.complete)
                      const Text(
                        'Close this group after all money has been reconciled.',
                      ),
                    if (kind == EntryKind.reverse)
                      Text(
                        'Reverse the recorded amount for entry #${widget.related}. Its original details stay in history.',
                      ),
                    if ([
                      EntryKind.cancel,
                      EntryKind.reopen,
                      EntryKind.reverse,
                    ].contains(kind))
                      input('Note', hint: 'Reason for this change'),
                  ] else ...[
                    if (mode == TripFormMode.expense)
                      choice('Payment source', kind, {
                        EntryKind.cashExpense: 'Collected group funds',
                        EntryKind.memberExpense: 'Paid personally by member',
                        EntryKind.liability: 'Unpaid bill',
                      }, (v) => kind = v),
                    if ([
                          TripFormMode.expense,
                          TripFormMode.contribution,
                        ].contains(mode) &&
                        kind != EntryKind.liability)
                      choice(
                        mode == TripFormMode.expense
                            ? 'Purchased by'
                            : 'Member',
                        member!,
                        {for (final m in g!.roster) m.id: m.name},
                        (v) {
                          member = v;
                          if (mode == TripFormMode.contribution &&
                              old == null) {
                            suggestContribution();
                          }
                        },
                      ),
                    if (kind == EntryKind.cashCount)
                      Text(
                        'Count only the cash held for this group. The ledger shows ${Money.format(g!.cash, currency)}. Enter the amount you actually hold.',
                      ),
                    if (mode == TripFormMode.payment &&
                        kind != EntryKind.cashCount)
                      Text(
                        [
                          g!.members[widget.member]?.name,
                          g!.events[widget.related]?.label,
                        ].whereType<String>().join(' · '),
                      ),
                    input(
                      'Amount',
                      number: true,
                      readOnly:
                          value('Quantity').isNotEmpty &&
                          value('Unit price').isNotEmpty,
                    ),
                    if (mode == TripFormMode.contribution)
                      choice('Payment method', method, {
                        for (final m in [
                          'Cash',
                          'Bank transfer',
                          'Mobile payment',
                          'Other',
                        ])
                          m: m,
                      }, (v) => method = v),
                    if (mode == TripFormMode.expense) ...[
                      input('Item', hint: 'Bottled water'),
                      choice('Category', category, {
                        for (final c in options) c: c,
                      }, (v) => category = v),
                      if (category == custom) input('Custom category'),
                    ],
                    dateRow(),
                    input(
                      'Note',
                      hint: kind == EntryKind.returnRefund
                          ? 'Why was this refund returned?'
                          : 'Optional',
                    ),
                    if (old != null) input('Reason for correction'),
                    if (mode == TripFormMode.expense)
                      ExpansionTile(
                        initiallyExpanded: advanced,
                        title: const Text('Quantity and receipt'),
                        children: [
                          input('Quantity', number: true, change: calculate),
                          input('Unit price', number: true, change: calculate),
                          photo('Receipt photo'),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(
                    busy
                        ? 'Saving…'
                        : mode == TripFormMode.create
                        ? 'Create group'
                        : mode == TripFormMode.action
                        ? 'Confirm'
                        : 'Save',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
