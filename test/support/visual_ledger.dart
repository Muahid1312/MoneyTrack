import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/features/groups/domain/group_fund.dart';

/// Only used with fresh test databases.
Future<int> seedVisualLedger(AppDatabase db, DateTime today) async {
  final wallets = WalletRepository(db),
      transactions = SqfliteTransactionRepository(db);
  await wallets.save(
    const Wallet(
      id: 1,
      name: 'Cash',
      currency: AppCurrency.afn,
      type: WalletType.cash,
      openingMinor: 850000,
    ),
  );
  await wallets.save(
    const Wallet(
      name: 'Travel account',
      currency: AppCurrency.usd,
      type: WalletType.bank,
      openingMinor: 12500,
    ),
  );
  final planning = PlanningRepository(db);
  for (final r in [
    (today.day, 18500, 'food', 'Lunch with friends'),
    (today.day, 125000, 'business', 'Translation'),
    (1, 2000000, 'salary', 'Payday'),
    (2, 45000, 'groceries', 'Weekly shop'),
    (3, 30000, 'transport', 'Bus fare'),
  ]) {
    final at = DateTime(today.year, today.month, r.$1.clamp(1, today.day), 9);
    await transactions.insert(
      TransactionModel(
        walletId: 1,
        currency: AppCurrency.afn,
        type: ['business', 'salary'].contains(r.$3)
            ? TransactionType.income
            : TransactionType.expense,
        amountMinor: r.$2,
        categoryId: r.$3,
        note: r.$4,
        occurredAt: at,
        createdAt: at,
        updatedAt: at,
      ),
    );
  }
  final goal = await planning.saveGoal(
    goalName: 'Emergency reserve',
    walletId: 1,
    targetMinor: 1000000,
    emergency: true,
  );
  await planning.goalEvent(goal, 500000, 'Emergency contribution');
  final repo = GroupRepository(db);
  final id = await repo.create(
    key: 'visual-trip',
    name: 'Paghman trip',
    currency: AppCurrency.afn,
    date: today,
    members: [
      'Ahmad',
      'Mahmood',
      'Omid',
      'Farid',
      'Mina',
      'Zahra',
      'Ali',
      'Laila',
      'Sami',
      'Nadia',
    ],
    expected: 30000,
  );
  for (final m in (await repo.get(id)).roster) {
    await repo.post(
      id,
      'paid-${m.id}',
      TripEntry(
        kind: EntryKind.contribution,
        member: m.id,
        at: today,
        method: 'Cash',
        amount: 30000,
      ),
    );
  }
  for (final r in [
    ('Transportation', 70000),
    ('Food', 90000),
    ('Drinks', 25000),
    ('Fruits', 30000),
    ('Snacks', 20000),
  ]) {
    await repo.post(
      id,
      'shop-${r.$1}',
      TripEntry(
        kind: EntryKind.cashExpense,
        member: 1,
        category: r.$1,
        at: today,
        label: r.$1 == 'Transportation'
            ? 'Minibus rental'
            : r.$1 == 'Food'
            ? 'Group lunch'
            : r.$1,
        amount: r.$2,
      ),
    );
  }
  return id;
}
