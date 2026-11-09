import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';

class InMemoryTransactionRepository implements TransactionRepository {
  InMemoryTransactionRepository([List<TransactionModel> seed = const []]) {
    for (final t in seed) {
      _items[++_seq] = t.copyWith(id: _seq);
    }
  }

  final Map<int, TransactionModel> _items = {};
  int _seq = 0;

  @override
  Future<void> clear() async => _items.clear();

  @override
  Future<void> delete(int id) async => _items.remove(id);

  @override
  Future<List<TransactionModel>> fetchAll() async => _items.values.toList();

  @override
  Future<TransactionModel> insert(TransactionModel tx) async {
    final saved = tx.copyWith(id: ++_seq);
    _items[_seq] = saved;
    return saved;
  }

  @override
  Future<void> update(TransactionModel tx) async => _items[tx.id!] = tx;
}

List<TransactionModel> sampleData(DateTime now) {
  TransactionModel t(TransactionType type, int minor, String cat, int daysAgo, String note,
      [int hour = 12]) {
    final d = DateTime(now.year, now.month, now.day - daysAgo, hour, 15);
    return TransactionModel(
      type: type,
      amountMinor: minor,
      categoryId: cat,
      note: note,
      occurredAt: d,
      createdAt: d,
      updatedAt: d,
    );
  }

  const e = TransactionType.expense;
  const i = TransactionType.income;
  return [
    t(i, 420000, 'salary', now.day - 1, 'Monthly salary', 9),
    t(i, 420000, 'salary', now.day + 29, 'Monthly salary', 9),
    t(i, 85000, 'freelance', 9, 'Logo design project', 16),
    t(e, 120000, 'housing', now.day - 2, 'Rent', 10),
    t(e, 120000, 'housing', now.day + 28, 'Rent', 10),
    t(e, 1850, 'food', 0, 'Coffee & croissant', 8),
    t(e, 6420, 'groceries', 0, 'Weekly groceries', 18),
    t(e, 2400, 'transport', 1, 'Taxi to office', 9),
    t(e, 4890, 'food', 1, 'Dinner with friends', 20),
    t(e, 12999, 'shopping', 2, 'Running shoes', 14),
    t(e, 8900, 'bills', 3, 'Internet bill', 11),
    t(e, 3200, 'entertainment', 4, 'Cinema tickets', 19),
    t(e, 2750, 'food', 5, 'Lunch', 13),
    t(e, 15400, 'health', 6, 'Pharmacy', 17),
    t(e, 5400, 'groceries', 8, 'Groceries', 18),
    t(e, 22000, 'education', 12, 'Online course', 21),
    t(e, 9800, 'transport', 15, 'Fuel', 8),
    t(e, 64000, 'travel', 34, 'Weekend trip', 10),
    t(e, 18000, 'shopping', 40, 'Jacket', 15),
    t(e, 31000, 'food', 45, 'Restaurants', 20),
    t(e, 9100, 'bills', 33, 'Electricity', 11),
    t(i, 40000, 'investments', 50, 'Dividends', 10),
  ];
}
