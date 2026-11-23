import 'dart:convert';
import '../../../core/constants/currency.dart';

typedef DataRow = Map<String, Object?>;

enum TripStage {
  planning('Planning'),
  active('Active'),
  settlement('Settlement pending'),
  completed('Completed'),
  cancelled('Cancelled');

  const TripStage(this.label);
  final String label;
}

enum EntryKind {
  contribution('Contribution'),
  cashExpense('Fund purchase'),
  memberExpense('Member purchase'),
  liability('Unpaid bill'),
  reimburse('Reimbursement'),
  payBill('Bill payment'),
  reverse('Correction'),
  confirm('Plan confirmed'),
  refund('Refund paid'),
  returnRefund('Refund returned'),
  complete('Completed'),
  reopen('Reopened'),
  cancel('Cancelled'),
  cashCount('Cash counted'),
  activate('Activated');

  const EntryKind(this.label);
  final String label;
  bool get purchase =>
      this == cashExpense || this == memberExpense || this == liability;
}

class FundError implements Exception {
  const FundError(this.message);
  final String message;
  @override
  String toString() => message;
}

void requireFund(bool condition, String message) {
  if (!condition) throw FundError(message);
}

String quantityText(int thousandths) {
  final whole = thousandths ~/ 1000;
  final tail = (thousandths % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return tail.isEmpty ? whole.toString() : '$whole.$tail';
}

int quantityCost(int thousandths, int unitMinor) {
  final cost =
      (BigInt.from(thousandths) * BigInt.from(unitMinor) + BigInt.from(500)) ~/
      BigInt.from(1000);
  requireFund(
    cost <= BigInt.from(AppInfo.maxAmountMinor),
    'The purchase total is too large.',
  );
  return cost.toInt();
}

class TripMember {
  TripMember(this.id, this.name, this.expected, this.archived);
  factory TripMember.fromRow(DataRow r) => TripMember(
    r['id'] as int,
    r['name'] as String,
    r['expected_minor'] as int,
    r['archived'] == 1,
  );
  final int id, expected;
  final String name;
  final bool archived;
}

class TripEntry {
  TripEntry({
    required this.kind,
    this.amount = 0,
    this.member,
    this.related,
    this.label = '',
    this.category = '',
    this.method = '',
    this.note = '',
    this.quantity,
    this.unit,
    this.allocation = const {},
    required this.at,
  });
  factory TripEntry.fromRow(DataRow r) => TripEntry(
    kind: EntryKind.values.byName(r['kind'] as String),
    amount: r['amount_minor'] as int,
    member: r['member_id'] as int?,
    related: r['related_id'] as int?,
    label: r['label'] as String,
    category: r['category'] as String,
    method: r['method'] as String,
    note: r['note'] as String,
    quantity: r['quantity'] as int?,
    unit: r['unit_minor'] as int?,
    allocation: {
      for (final e in (jsonDecode(r['allocation'] as String) as Map).entries)
        int.parse(e.key as String): e.value as int,
    },
    at: DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int),
  );
  final EntryKind kind;
  final int amount;
  final int? member, related, quantity, unit;
  final String label, category, method, note;
  final DateTime at;
  final Map<int, int> allocation;
  DataRow get fields => {
    'kind': kind.name,
    'amount_minor': amount,
    'member_id': member,
    'related_id': related,
    'label': label.trim(),
    'category': category.trim(),
    'method': method.trim(),
    'note': note.trim(),
    'quantity': quantity,
    'unit_minor': unit,
    'occurred_at': at.millisecondsSinceEpoch,
    'allocation': jsonEncode({
      for (final e in allocation.entries) e.key.toString(): e.value,
    }),
  };
}

Map<int, int> proportionalRefunds(Map<int, int> weights, int pool) {
  requireFund(
    pool >= 0 && weights.values.every((n) => n >= 0),
    'Invalid refund weights or pool.',
  );
  final contributors = weights.entries.where((e) => e.value > 0).toList();
  final total = contributors.fold(
    BigInt.zero,
    (n, e) => n + BigInt.from(e.value),
  );
  if (total == BigInt.zero) {
    requireFund(pool == 0, 'A surplus needs a contributing member.');
    return {};
  }
  final result = <int, int>{}, remainders = <(int, BigInt)>[];
  var remaining = pool;
  for (final e in contributors) {
    final numerator = BigInt.from(pool) * BigInt.from(e.value);
    final floor = (numerator ~/ total).toInt();
    result[e.key] = floor;
    remaining -= floor;
    remainders.add((e.key, numerator % total));
  }
  remainders.sort((a, b) {
    final order = b.$2.compareTo(a.$2);
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  for (var i = 0; i < remaining; i++) {
    final id = remainders[i].$1;
    result[id] = result[id]! + 1;
  }
  return result;
}

/// Replaying records in commit order also validates a restored journal.
class GroupFund {
  GroupFund(this.project, this.members);
  final DataRow project;
  final Map<int, TripMember> members;
  final events = <int, TripEntry>{},
      net = <int, int>{},
      paid = <int, int>{},
      obligations = <int, int>{};
  final reversed = <int>{};
  Map<int, int> allocation = {};
  final countVariances = <int, int>{};
  bool get unmatchedCount =>
      countVariances.isNotEmpty && countVariances.values.last != 0;
  int cash = 0, spent = 0, reimbursed = 0;
  TripStage stage = TripStage.planning;
  int get id => project['id'] as int;
  String get name => project['name'] as String;
  AppCurrency get currency =>
      AppCurrency.requireCode(project['currency'] as String);
  int _revision = 0;
  int get revision => _revision;
  bool get editable => stage == TripStage.planning || stage == TripStage.active;
  Iterable<TripMember> get roster => members.values.where((e) => !e.archived);
  int get expected => roster.fold(0, (n, m) => n + m.expected);
  int get outstanding => roster.fold(0, (n, m) => n + memberDue(m));
  int memberDue(TripMember m) {
    final due = m.expected - (net[m.id] ?? 0);
    return due > 0 ? due : 0;
  }

  int get collected => net.values.fold(0, (a, b) => a + b);
  int get refunded => paid.values.fold(0, (a, b) => a + b);
  int owed(EntryKind kind) => obligations.entries
      .where((e) => events[e.key]?.kind == kind)
      .fold(0, (n, e) => n + e.value);
  int get surplus =>
      cash - owed(EntryKind.memberExpense) - owed(EntryKind.liability);
  int dueRefund(int m) => (allocation[m] ?? 0) - (paid[m] ?? 0);
  bool get frozen =>
      stage == TripStage.settlement || stage == TripStage.completed;
  Map<int, int> preview() {
    requireFund(
      !unmatchedCount,
      'Resolve the cash count difference and count the fund again.',
    );
    requireFund(
      surplus >= 0,
      'Cover the deficit before confirming a refund plan.',
    );
    final next = proportionalRefunds(net, surplus + refunded);
    requireFund(
      paid.entries.every((e) => e.value <= (next[e.key] ?? 0)),
      'A previous refund exceeds the revised share. Record money returned by that member before confirming.',
    );
    return next;
  }

  void apply(int eventId, TripEntry e) {
    final k = e.kind, a = e.amount, m = e.member, link = e.related;
    requireFund(eventId > revision, 'Invalid journal order.');
    requireFund(
      m == null || members.containsKey(m),
      'Choose a member of this group.',
    );
    final money =
        k == EntryKind.contribution ||
        k.purchase ||
        [
          EntryKind.reimburse,
          EntryKind.payBill,
          EntryKind.refund,
          EntryKind.returnRefund,
        ].contains(k);
    requireFund(
      money
          ? a > 0 && a <= AppInfo.maxAmountMinor
          : k == EntryKind.cashCount
          ? a >= 0 && a <= AppInfo.maxAmountMinor
          : a == 0,
      'Enter a valid positive amount.',
    );
    requireFund(
      (e.quantity == null && e.unit == null) ||
          (k.purchase &&
              e.quantity != null &&
              e.unit != null &&
              e.quantity! > 0 &&
              e.unit! > 0 &&
              quantityCost(e.quantity!, e.unit!) == a),
      'Quantity times unit price must equal the expense.',
    );
    requireFund(
      e.allocation.isEmpty || k == EntryKind.confirm,
      'Unexpected refund allocation.',
    );
    final linked = [
      EntryKind.reverse,
      EntryKind.reimburse,
      EntryKind.payBill,
    ].contains(k);
    requireFund(linked == (link != null), 'Invalid linked journal record.');
    requireFund(
      m == null ||
          [
            EntryKind.contribution,
            EntryKind.cashExpense,
            EntryKind.memberExpense,
            EntryKind.refund,
            EntryKind.returnRefund,
            EntryKind.reimburse,
            EntryKind.liability,
            EntryKind.payBill,
          ].contains(k),
      'Unexpected member on journal record.',
    );
    final source = events[link];
    if ([
      EntryKind.contribution,
      EntryKind.cashExpense,
      EntryKind.memberExpense,
      EntryKind.liability,
      EntryKind.reverse,
      EntryKind.returnRefund,
    ].contains(k)) {
      requireFund(editable, 'Reopen the group before changing its records.');
    }
    if (k.purchase) {
      requireFund(
        e.label.trim().isNotEmpty && e.category.trim().isNotEmpty,
        'Enter the item and its category.',
      );
    }
    switch (k) {
      case EntryKind.contribution:
        requireFund(
          m != null && e.method.trim().isNotEmpty,
          'Choose a member and payment method.',
        );
        net[m!] = (net[m] ?? 0) + a;
        cash += a;
      case EntryKind.cashExpense:
        requireFund(m != null, 'Choose who made the purchase.');
        requireFund(
          a <= cash,
          'The group has insufficient cash. Choose a member payment or record an unpaid bill.',
        );
        cash -= a;
        spent += a;
      case EntryKind.memberExpense:
      case EntryKind.liability:
        requireFund(
          k == EntryKind.liability || m != null,
          'Choose the member who paid.',
        );
        obligations[eventId] = a;
        spent += a;
      case EntryKind.reimburse:
      case EntryKind.payBill:
        requireFund(
          stage != TripStage.completed,
          'Reopen the completed group first.',
        );
        requireFund(
          source?.kind ==
                  (k == EntryKind.reimburse
                      ? EntryKind.memberExpense
                      : EntryKind.liability) &&
              m == source?.member &&
              a <= (obligations[link] ?? 0),
          'Payment exceeds the outstanding amount for this purchase.',
        );
        requireFund(a <= cash, 'There is insufficient group cash.');
        obligations[link!] = obligations[link]! - a;
        cash -= a;
        if (k == EntryKind.reimburse) reimbursed += a;
      case EntryKind.reverse:
        requireFund(
          source != null &&
              !reversed.contains(link) &&
              e.note.trim().isNotEmpty,
          'Choose an unreversed record and give a reason.',
        );
        final s = source!;
        if (s.kind == EntryKind.contribution) {
          net[s.member!] = net[s.member!]! - s.amount;
          cash -= s.amount;
        } else if (s.kind.purchase) {
          if (s.kind == EntryKind.cashExpense) {
            cash += s.amount;
          } else {
            requireFund(
              obligations[link] == s.amount,
              'Record any repayment returned to the group before correcting this purchase.',
            );
            obligations[link!] = 0;
          }
          spent -= s.amount;
        } else if (s.kind == EntryKind.reimburse ||
            s.kind == EntryKind.payBill) {
          obligations[s.related!] = obligations[s.related!]! + s.amount;
          cash += s.amount;
          if (s.kind == EntryKind.reimburse) reimbursed -= s.amount;
        } else {
          throw const FundError('This entry cannot be voided.');
        }
        reversed.add(link!);
      case EntryKind.cashCount:
        requireFund(
          stage != TripStage.completed,
          'Reopen the completed group before recording a cash count.',
        );
        countVariances[eventId] = a - cash;
      case EntryKind.activate:
        requireFund(
          stage == TripStage.planning,
          'Only a planned group can be started.',
        );
        stage = TripStage.active;
      case EntryKind.cancel:
        requireFund(
          editable && e.note.trim().isNotEmpty,
          'Give a reason for cancelling an open group.',
        );
        stage = TripStage.cancelled;
      case EntryKind.confirm:
        requireFund(
          editable || stage == TripStage.cancelled,
          'This group already has a settlement plan.',
        );
        final required = preview();
        requireFund(
          required.length == e.allocation.length &&
              required.entries.every((x) => e.allocation[x.key] == x.value),
          'The refund preview changed. Review it again.',
        );
        allocation = Map.unmodifiable(e.allocation);
        stage = TripStage.settlement;
      case EntryKind.refund:
        requireFund(
          stage == TripStage.settlement &&
              !unmatchedCount &&
              m != null &&
              a <= dueRefund(m) &&
              a <= surplus,
          'Payment exceeds the unpaid refund or available surplus.',
        );
        paid[m!] = (paid[m] ?? 0) + a;
        cash -= a;
      case EntryKind.returnRefund:
        requireFund(
          m != null && a <= (paid[m] ?? 0) && e.note.trim().isNotEmpty,
          'Record the amount actually returned and a reason.',
        );
        paid[m!] = paid[m]! - a;
        cash += a;
      case EntryKind.complete:
        requireFund(
          stage == TripStage.settlement &&
              !unmatchedCount &&
              cash == 0 &&
              obligations.values.every((v) => v == 0) &&
              allocation.keys.every((id) => dueRefund(id) == 0),
          'Pay all bills, reimbursements and refunds before completing.',
        );
        stage = TripStage.completed;
      case EntryKind.reopen:
        requireFund(
          (frozen || stage == TripStage.cancelled) && e.note.trim().isNotEmpty,
          'Give a reason for reopening this group.',
        );
        allocation = {};
        stage = TripStage.active;
    }
    if (money && stage == TripStage.planning) stage = TripStage.active;
    events[eventId] = e;
    _revision = eventId;
  }
}
