import '../../../core/constants/currency.dart';

typedef FundRow = Map<String, Object?>;

class FundRule implements Exception {
  const FundRule(this.message);
  final String message;

  @override
  String toString() => message;
}

void requireManaged(bool condition, String message) {
  if (!condition) throw FundRule(message);
}

enum FundStatus { active, settlementPending, completed, cancelled }

enum FundIcon { fund, groceries, repairs, shopping, event }

enum FundEventKind {
  funding,
  fundingReversal,
  purchase,
  purchaseReversal,
  refund,
  refundReversal,
  reimburseDirect,
  reimburseCash,
  reimbursementReversal,
}

class ManagedFund {
  ManagedFund.fromRow(FundRow row)
    : id = row['id'] as int,
      name = row['name'] as String,
      provider = row['provider'] as String,
      currency = AppCurrency.requireCode(row['currency'] as String),
      opened = DateTime.fromMillisecondsSinceEpoch(row['opened_at'] as int),
      description = row['description'] as String,
      purpose = row['purpose'] as String,
      expected = row['expected_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['expected_at'] as int),
      notes = row['notes'] as String,
      icon = FundIcon.values.byName(row['icon'] as String),
      status = FundStatus.values.byName(row['status'] as String);

  final int id;
  final String name, provider, description, purpose, notes;
  final AppCurrency currency;
  final DateTime opened;
  final DateTime? expected;
  final FundIcon icon;
  final FundStatus status;
}

class FundEvent {
  FundEvent.fromRow(FundRow row)
    : id = row['id'] as int,
      kind = FundEventKind.values.byName(row['kind'] as String),
      target = row['target_id'] as int?,
      cash = row['cash_minor'] as int,
      personal = row['personal_minor'] as int,
      date = DateTime.fromMillisecondsSinceEpoch(row['occurred_at'] as int),
      party = row['party'] as String,
      method = row['method'] as String,
      note = row['note'] as String;

  final int id, cash, personal;
  final int? target;
  final FundEventKind kind;
  final DateTime date;
  final String party, method, note;
  int get total => cash + personal;
}

/// A quantity has three decimal places. Multiply before rounding once per line.
class PurchaseLine {
  PurchaseLine({
    required String name,
    String category = '',
    this.quantityMilli,
    String unit = '',
    this.unitMinor,
    int? totalMinor,
  }) : name = name.trim(),
       category = category.trim(),
       unit = unit.trim(),
       total = _total(quantityMilli, unitMinor, totalMinor) {
    requireManaged(
      this.name.isNotEmpty && this.name.length <= 120,
      'Enter an item name of 1 to 120 characters.',
    );
    requireManaged(
      this.category.length <= 120 && this.unit.length <= 40,
      'Category or unit is too long.',
    );
    requireManaged(
      quantityMilli == null ? this.unit.isEmpty : this.unit.isNotEmpty,
      'Enter the unit when recording a quantity.',
    );
  }

  factory PurchaseLine.fromRow(FundRow r) => PurchaseLine(
    name: r['name'] as String,
    category: r['category'] as String,
    quantityMilli: r['quantity_milli'] as int?,
    unit: r['unit'] as String,
    unitMinor: r['unit_minor'] as int?,
    totalMinor: r['total_minor'] as int,
  );

  final String name, category, unit;
  final int? quantityMilli, unitMinor;
  final int total;

  static String formatQuantity(int milli) =>
      '${milli ~/ 1000}.${(milli % 1000).toString().padLeft(3, '0')}'
          .replaceFirst(RegExp(r'\.?0+$'), '');

  static int? parseQuantity(String input) {
    final text = input.trim();
    if (!RegExp(r'^\d{1,6}(\.\d{1,3})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final quantity =
        int.parse(parts.first) * 1000 +
        (parts.length == 1 ? 0 : int.parse(parts.last.padRight(3, '0')));
    return quantity > 0 ? quantity : null;
  }

  static int _total(int? quantity, int? unitPrice, int? manualTotal) {
    if (quantity == null && unitPrice == null) {
      requireManaged(
        manualTotal != null &&
            manualTotal > 0 &&
            manualTotal <= AppInfo.maxAmountMinor,
        'Enter a valid item amount.',
      );
      return manualTotal!;
    }
    requireManaged(
      quantity != null &&
          quantity > 0 &&
          quantity <= 999999999 &&
          unitPrice != null &&
          unitPrice > 0 &&
          unitPrice <= AppInfo.maxAmountMinor,
      'Enter a valid quantity and unit price.',
    );
    final value =
        (BigInt.from(quantity!) * BigInt.from(unitPrice!) + BigInt.from(500)) ~/
        BigInt.from(1000);
    requireManaged(
      value > BigInt.zero && value <= BigInt.from(AppInfo.maxAmountMinor),
      'The calculated item amount is outside the supported range.',
    );
    final result = value.toInt();
    requireManaged(
      manualTotal == null || manualTotal == result,
      'The item amount must match its quantity and unit price.',
    );
    return result;
  }

  FundRow toRow() => {
    'name': name,
    'category': category,
    'quantity_milli': quantityMilli,
    'unit': unit,
    'unit_minor': unitMinor,
    'total_minor': total,
  };
}

class ManagedLedger {
  ManagedLedger(this.fund);
  final ManagedFund fund;
  final _events = <int, FundEvent>{};
  final _undone = <int>{};
  final _cashRefunds = <int, int>{};
  final _personalRefunds = <int, int>{};
  final _reimbursements = <int, int>{};
  int _received = 0, _cash = 0, _cashSpent = 0, _advanced = 0;
  int _direct = 0, _fundReimbursements = 0;

  List<FundEvent> get events => List.unmodifiable(_events.values);
  FundEvent? event(int id) => _events[id];
  int get received => _received;
  int get cash => _cash;
  int get cashSpent => _cashSpent;
  int get expenses => _cashSpent + _advanced;
  int get advanced => _advanced;
  int get directReimbursements => _direct;
  int get fundReimbursements => _fundReimbursements;
  int get outstanding => _advanced - _direct - _fundReimbursements;
  int get netReturnable => cash >= outstanding ? cash - outstanding : 0;
  int get shortfall => cash >= outstanding ? 0 : outstanding - cash;

  bool reversed(int id) => _undone.contains(id);
  int refundableCash(int id) => _availablePurchasePart(id, personal: false);
  int outstandingFor(int id) => _availablePurchasePart(id, personal: true);

  int _availablePurchasePart(int id, {required bool personal}) {
    final purchase = _events[id];
    if (purchase?.kind != FundEventKind.purchase || reversed(id)) return 0;
    return personal
        ? purchase!.personal -
              (_personalRefunds[id] ?? 0) -
              (_reimbursements[id] ?? 0)
        : purchase!.cash - (_cashRefunds[id] ?? 0);
  }

  bool hasPurchaseAdjustments(int id) =>
      (_cashRefunds[id] ?? 0) > 0 ||
      (_personalRefunds[id] ?? 0) > 0 ||
      (_reimbursements[id] ?? 0) > 0;

  void apply(FundEvent event) {
    final target = _events[event.target];
    final kind = event.kind;
    final cash = event.cash;
    final personal = event.personal;
    final total = event.total;
    requireManaged(
      cash >= 0 &&
          personal >= 0 &&
          total > 0 &&
          total <= AppInfo.maxAmountMinor &&
          !_events.containsKey(event.id),
      'Invalid fund posting.',
    );
    requireManaged(
      event.method.trim().isNotEmpty && event.party.trim().isNotEmpty,
      'Each movement needs a party and payment method.',
    );

    switch (kind) {
      case FundEventKind.funding:
        requireManaged(
          (event.target == null ||
                  (target?.kind == FundEventKind.funding &&
                      !reversed(target!.id))) &&
              personal == 0,
          'Invalid funding record.',
        );
        _received += cash;
        _cash += cash;
      case FundEventKind.fundingReversal:
        requireManaged(
          target?.kind == FundEventKind.funding &&
              !reversed(target!.id) &&
              target.cash == cash &&
              personal == 0,
          'Only unreversed funding can be reversed.',
        );
        _requireCash(cash);
        _received -= cash;
        _cash -= cash;
        _undone.add(target!.id);
      case FundEventKind.purchase:
        requireManaged(
          event.target == null ||
              (target?.kind == FundEventKind.purchase && reversed(target!.id)),
          'Invalid purchase record.',
        );
        _requireCash(cash);
        _cash -= cash;
        _cashSpent += cash;
        _advanced += personal;
      case FundEventKind.purchaseReversal:
        requireManaged(
          target?.kind == FundEventKind.purchase &&
              !reversed(target!.id) &&
              target.cash == cash &&
              target.personal == personal,
          'Only unreversed purchases can be reversed.',
        );
        requireManaged(
          !hasPurchaseAdjustments(target!.id),
          'Resolve existing refunds or reimbursements before reversing this purchase.',
        );
        _cash += cash;
        _cashSpent -= cash;
        _advanced -= personal;
        _undone.add(target.id);
      case FundEventKind.refund:
        final purchase = _requirePurchase(target);
        requireManaged(
          cash <= refundableCash(purchase) &&
              personal <= outstandingFor(purchase),
          'The refund exceeds the purchase’s remaining cash or unreimbursed personal amount.',
        );
        _cashRefunds.update(purchase, (v) => v + cash, ifAbsent: () => cash);
        _personalRefunds.update(
          purchase,
          (v) => v + personal,
          ifAbsent: () => personal,
        );
        _cash += cash;
        _cashSpent -= cash;
        _advanced -= personal;
      case FundEventKind.refundReversal:
        requireManaged(
          target?.kind == FundEventKind.refund &&
              !reversed(target!.id) &&
              target.cash == cash &&
              target.personal == personal,
          'Only an unreversed refund can be reversed.',
        );
        _requireCash(cash);
        final purchase = _requirePurchase(_events[target!.target]);
        _cashRefunds[purchase] = _cashRefunds[purchase]! - cash;
        _personalRefunds[purchase] = _personalRefunds[purchase]! - personal;
        _cash -= cash;
        _cashSpent += cash;
        _advanced += personal;
        _undone.add(target.id);
      case FundEventKind.reimburseDirect:
      case FundEventKind.reimburseCash:
        final purchase = _requirePurchase(target);
        final fromFund = kind == FundEventKind.reimburseCash;
        requireManaged(
          (fromFund ? personal == 0 : cash == 0) &&
              total <= outstandingFor(purchase),
          'Enter an amount up to this purchase’s outstanding advance.',
        );
        _requireCash(cash);
        _cash -= cash;
        _fundReimbursements += cash;
        _direct += personal;
        _reimbursements.update(
          purchase,
          (v) => v + total,
          ifAbsent: () => total,
        );
      case FundEventKind.reimbursementReversal:
        requireManaged(
          target != null &&
              !reversed(target.id) &&
              (target.kind == FundEventKind.reimburseCash ||
                  target.kind == FundEventKind.reimburseDirect) &&
              target.cash == cash &&
              target.personal == personal,
          'Only an unreversed reimbursement can be reversed.',
        );
        _cash += cash;
        _fundReimbursements -= cash;
        _direct -= personal;
        _reimbursements[target!.target!] =
            _reimbursements[target.target!]! - total;
        _undone.add(target.id);
    }
    _events[event.id] = event;
  }

  int _requirePurchase(FundEvent? target) {
    requireManaged(
      target?.kind == FundEventKind.purchase && !reversed(target!.id),
      'Select an active purchase from this fund.',
    );
    return target!.id;
  }

  void _requireCash(int amount) => requireManaged(
    amount <= cash,
    'Entrusted cash is insufficient. Add funding or record a personal advance.',
  );
}
