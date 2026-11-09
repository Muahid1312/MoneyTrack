import '../../core/constants/currency.dart';

enum WalletType {
  cash('Cash'), bank('Bank account'), mobileMoney('Mobile money'),
  savings('Savings'), other('Other');
  const WalletType(this.label);
  final String label;
}

class Wallet {
  const Wallet({this.id, required this.name, required this.type,
    required this.currency, this.openingMinor = 0, this.archived = false});
  final int? id;
  final String name;
  final WalletType type;
  final AppCurrency currency;
  final int openingMinor;
  final bool archived;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id, 'name': name.trim(), 'type': type.name,
    'currency': currency.code, 'opening_minor': openingMinor,
    'archived': archived ? 1 : 0,
  };
  factory Wallet.fromMap(Map<String, Object?> m) => Wallet(
    id: m['id'] as int, name: m['name'] as String,
    type: WalletType.values.byName(m['type'] as String),
    currency: AppCurrency.requireCode(m['currency'] as String),
    openingMinor: m['opening_minor'] as int, archived: m['archived'] == 1,
  );
}

class WalletTransfer {
  const WalletTransfer({this.id, required this.sourceId,
    required this.destinationId, required this.sourceMinor,
    required this.destinationMinor, required this.rate,
    required this.sourceCurrency, required this.destinationCurrency,
    required this.occurredAt, this.note = ''});
  final int? id;
  final int sourceId, destinationId, sourceMinor, destinationMinor;
  final AppCurrency sourceCurrency, destinationCurrency;
  final String rate, note;
  final DateTime occurredAt;
  Map<String, Object?> toMap() => {
    'source_id': sourceId, 'destination_id': destinationId,
    'source_minor': sourceMinor, 'destination_minor': destinationMinor,
    'source_currency': sourceCurrency.code,
    'destination_currency': destinationCurrency.code,
    'rate': rate, 'note': note,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
  };
  factory WalletTransfer.fromMap(Map<String, Object?> m) => WalletTransfer(
    id: m['id'] as int, sourceId: m['source_id'] as int,
    destinationId: m['destination_id'] as int,
    sourceMinor: m['source_minor'] as int,
    destinationMinor: m['destination_minor'] as int,
    sourceCurrency: AppCurrency.requireCode(m['source_currency'] as String),
    destinationCurrency: AppCurrency.requireCode(m['destination_currency'] as String),
    rate: m['rate'] as String, note: m['note'] as String,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int),
  );
}
