import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/utils/amount_input.dart';
import 'package:moneytrack/core/utils/csv_exporter.dart';
import 'package:moneytrack/core/utils/money.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:moneytrack/features/statistics/domain/finance_calculator.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:moneytrack/features/wallets/domain/exchange_rate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TransactionModel entry({int walletId = 1, AppCurrency currency = AppCurrency.usd,
    int amount = 100, TransactionType type = TransactionType.income}) {
  final now = DateTime(2026, 11, 8);
  return TransactionModel(walletId: walletId, currency: currency, type: type,
    amountMinor: amount, categoryId: type.isIncome ? 'salary' : 'food',
    occurredAt: now, createdAt: now, updatedAt: now);
}

const legacySql = '''CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL CHECK(type IN ('income','expense')),
  amount_minor INTEGER NOT NULL CHECK(amount_minor>0),
  category_id TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
  occurred_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
)''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Fixed-point currency', () {
    test('supports zero, two and three decimals without floating point', () {
      expect(Money.parseMinor('12', AppCurrency.jpy), 12);
      expect(Money.parseMinor('12.1', AppCurrency.jpy), isNull);
      expect(Money.parseMinor('0.001', AppCurrency.kwd), 1);
      expect(Money.format(1001, AppCurrency.kwd), 'KD1.001');
      expect(Money.format(99, AppCurrency.jpy), '¥99');
      expect(Money.parseMinor('1,23'), isNull);
      expect(Money.parseMinor('99999999999999999999999999'), isNull);
      expect(AmountInput('', AppCurrency.jpy).appendDecimal().raw, '');
      expect(AmountInput.fromMinor(1234, AppCurrency.kwd).minor, 1234);
      expect(AmountInput('', AppCurrency.kwd).appendDecimal().appendDigit(0)
          .appendDigit(0).appendDigit(1).appendDigit(9).minor, 1);
    });
    test('manual rates round half up and account for both precisions', () {
      expect(ExchangeRate.parse('0.5').convert(1, AppCurrency.usd, AppCurrency.eur), 1);
      expect(ExchangeRate.parse('70.125').convert(100, AppCurrency.usd, AppCurrency.afn), 7013);
      expect(ExchangeRate.parse('2').convert(1, AppCurrency.jpy, AppCurrency.kwd), 2000);
      expect(ExchangeRate.parse('150').convert(100, AppCurrency.usd, AppCurrency.jpy), 150);
      for (final rate in ['0', '-1', 'NaN', '1e3', '1.1234567890123']) {
        expect(() => ExchangeRate.parse(rate), throwsFormatException);
      }
      expect(() => ExchangeRate.parse('0.000001').convert(1, AppCurrency.usd, AppCurrency.jpy), throwsArgumentError);
      expect(() => ExchangeRate.parse('100000000000').convert(AppInfo.maxAmountMinor, AppCurrency.usd, AppCurrency.eur), throwsArgumentError);
    });
    test('mixed currencies cannot be silently aggregated or relabelled in CSV', () {
      final data = [entry(), entry(currency: AppCurrency.afn)];
      expect(() => FinanceCalculator.totals(data), throwsArgumentError);
      expect(() => FinanceCalculator.balance(data), throwsArgumentError);
      final csv = CsvExporter.build(data, 'EUR');
      expect(csv, contains(',USD'));
      expect(csv, contains(',AFN'));
    });
  });

  group('SQLite wallet ledger', () {
    late Directory dir;
    late AppDatabase db;
    late WalletRepository wallets;
    late SqfliteTransactionRepository transactions;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moneytrack-test-');
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/ledger.db');
      wallets = WalletRepository(db);
      transactions = SqfliteTransactionRepository(db);
    });
    tearDown(() async { await db.close(); await dir.delete(recursive: true); });

    Future<int> create({AppCurrency currency = AppCurrency.usd, int opening = 0}) async {
      await wallets.save(Wallet(name: 'Savings', type: WalletType.savings,
        currency: currency, openingMinor: opening));
      return (await wallets.fetch()).wallets.last.id!;
    }

    test('opening balances are not income; edits, moves and deletion derive balances', () async {
      final id = await create(opening: 10000);
      final income = await transactions.insert(entry(walletId: id, amount: 500));
      final expense = await transactions.insert(entry(walletId: id, amount: 200, type: TransactionType.expense));
      expect((await wallets.fetch()).balances[id], 10300);
      expect(FinanceCalculator.totals(await transactions.fetchAll()).income, 500);
      await transactions.update(expense.copyWith(amountMinor: 300));
      expect((await wallets.fetch()).balances[id], 10200);
      await transactions.update(income.copyWith(walletId: 1));
      expect((await wallets.fetch()).balances[id], 9700);
      expect((await wallets.fetch()).balances[1], 500);
      await transactions.delete(expense.id!);
      expect((await wallets.fetch()).balances[id], 10000);
    });

    test('transfer is atomic and never appears in income/expense totals', () async {
      final source = await create(opening: 10000);
      final dest = await create();
      await wallets.transfer(sourceId: source, destinationId: dest, sourceMinor: 2500,
        rate: '1', occurredAt: DateTime(2026));
      final state = await wallets.fetch();
      expect(state.balances[source], 7500);
      expect(state.balances[dest], 2500);
      expect(FinanceCalculator.totals(await transactions.fetchAll()).count, 0);
      await wallets.deleteTransfer(state.transfers.single.id!);
      expect((await wallets.fetch()).balances[source], 10000);
      expect((await wallets.fetch()).balances[dest], 0);
    });

    test('cross-currency transfer preserves both amounts and historical rate on reopen', () async {
      final source = await create(opening: 10000);
      final dest = await create(currency: AppCurrency.afn);
      await wallets.transfer(sourceId: source, destinationId: dest, sourceMinor: 100,
        rate: '70.125', occurredAt: DateTime(2026, 10, 1));
      await db.close();
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/ledger.db');
      wallets = WalletRepository(db);
      final state = await wallets.fetch();
      expect(state.balances[source], 9900);
      expect(state.balances[dest], 7013);
      expect(state.transfers.single.rate, '70.125');
      expect(state.transfers.single.sourceCurrency, AppCurrency.usd);
      expect(state.transfers.single.destinationCurrency, AppCurrency.afn);
    });

    test('invalid operations leave ledger unchanged and archive keeps history', () async {
      final source = await create(opening: 100);
      final dest = await create();
      for (final args in [(source, source, 50, '1'), (source, dest, 0, '1'),
          (source, dest, 101, '1'), (source, dest, 50, '2'), (source, 999, 50, '1')]) {
        await expectLater(wallets.transfer(sourceId: args.$1, destinationId: args.$2,
          sourceMinor: args.$3, rate: args.$4, occurredAt: DateTime(2026)), throwsArgumentError);
      }
      expect((await wallets.fetch()).transfers, isEmpty);
      await wallets.save(Wallet(id: dest, name: 'Archived', type: WalletType.bank,
        currency: AppCurrency.usd, archived: true));
      await expectLater(transactions.insert(entry(walletId: dest)), throwsA(isA<DatabaseException>()));
      await expectLater(wallets.transfer(sourceId: source, destinationId: dest,
        sourceMinor: 10, rate: '1', occurredAt: DateTime(2026)), throwsArgumentError);
      await expectLater(transactions.insert(entry(walletId: source, currency: AppCurrency.afn)), throwsA(isA<DatabaseException>()));
      await expectLater(wallets.save(Wallet(id: source, name: 'Changed', type: WalletType.cash,
        currency: AppCurrency.eur)), throwsA(isA<DatabaseException>()));
      expect((await wallets.fetch()).balances[source], 100);
    });

    test('a SQLite transaction rolls back a valid write when a later write fails', () async {
      await expectLater(db.db.transaction((txn) async {
        await txn.insert('transactions', entry(amount: 500).toMap());
        await txn.insert('transactions', entry(walletId: 999).toMap());
      }), throwsA(isA<DatabaseException>()));
      expect(await transactions.fetchAll(), isEmpty);
      expect((await wallets.fetch()).balances[1], 0);
    });

    test('clear data reverses transactions, transfers and opening balances together', () async {
      final id = await create(opening: 1000);
      await wallets.transfer(sourceId: id, destinationId: 1, sourceMinor: 100,
        rate: '1', occurredAt: DateTime(2026));
      await transactions.insert(entry(amount: 50));
      await transactions.clear();
      final state = await wallets.fetch();
      expect(state.transfers, isEmpty);
      expect(state.balances.values, everyElement(0));
    });
  });

  group('Version 1 upgrades', () {
    for (final currency in [AppCurrency.usd, AppCurrency.afn, AppCurrency.eur]) {
      test('preserves IDs, amounts, categories, notes, dates and prefs for ${currency.code}', () async {
        final dir = await Directory.systemTemp.createTemp('moneytrack-v1-');
        final path = '${dir.path}/legacy.db';
        final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
          version: 1, onCreate: (db, _) => db.execute(legacySql)));
        final row = {'id': 42, 'type': 'expense', 'amount_minor': 12345,
          'category_id': 'food', 'note': 'Legacy ؋', 'occurred_at': 123,
          'created_at': 100, 'updated_at': 124};
        await old.insert('transactions', row);
        await old.close();
        SharedPreferences.setMockInitialValues({'currency': currency.code,
          'user_name': 'Legacy user', 'monthly_budget_minor': 50000});
        final prefs = SettingsRepository(await SharedPreferences.getInstance());
        final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path,
          legacyCurrency: prefs.load().currency);
        try {
          final migrated = (await db.db.query('transactions')).single;
          for (final field in row.entries) { expect(migrated[field.key], field.value); }
          expect(migrated['wallet_id'], 1);
          expect(migrated['currency'], currency.code);
          expect(await db.db.getVersion(), AppDatabase.schemaVersion);
          expect((await WalletRepository(db).fetch()).balances[1], -12345);
          expect(prefs.load().userName, 'Legacy user');
          expect(prefs.load().monthlyBudgetMinor, 50000);
          expect(await db.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally { await db.close(); await dir.delete(recursive: true); }
      });
    }

    test('migration failure restores the v1 schema and data', () async {
      final dir = await Directory.systemTemp.createTemp('moneytrack-rollback-');
      final path = '${dir.path}/legacy.db';
      var old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
        version: 1, onCreate: (db, _) async {
          await db.execute(legacySql);
          // Force a late migration failure after wallet creation and ALTER TABLE.
          await db.execute('CREATE TABLE transfers (legacy_marker TEXT)');
        }));
      final legacy = entry().toMap()..remove('wallet_id')..remove('currency')
        ..removeWhere((key, _) => key.startsWith('project_') || key == 'client_receipt' || key == 'payment_reference' || key == 'recurring_rule_id' || key == 'occurrence_date');
      await old.insert('transactions', legacy);
      await old.close();
      await expectLater(AppDatabase.open(factory: databaseFactoryFfi, path: path), throwsA(isA<DatabaseException>()));
      old = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(await old.getVersion(), 1);
        expect((await old.query('transactions')).length, 1);
        final columns = await old.rawQuery('PRAGMA table_info(transactions)');
        expect(columns.any((c) => c['name'] == 'wallet_id'), isFalse);
        expect(await old.rawQuery("SELECT name FROM sqlite_master WHERE name='wallets'"), isEmpty);
      } finally { await old.close(); await dir.delete(recursive: true); }
    });
  });

  test('reporting preference scopes totals and preserves currency-specific budgets', () async {
    SharedPreferences.setMockInitialValues({'currency': 'USD', 'monthly_budget_minor': 12345});
    final settings = SettingsRepository(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    final controller = container.read(settingsProvider.notifier);
    expect(container.read(settingsProvider).monthlyBudgetMinor, 12345);
    await controller.setCurrency(AppCurrency.afn);
    expect(container.read(settingsProvider).monthlyBudgetMinor, 0);
    await controller.setMonthlyBudget(700);
    await controller.setCurrency(AppCurrency.usd);
    expect(container.read(settingsProvider).monthlyBudgetMinor, 12345);
    await controller.setCurrency(AppCurrency.afn);
    expect(container.read(settingsProvider).monthlyBudgetMinor, 700);
    // Wallet repository is opt-in for old UI test fakes; no global singleton.
    expect(container.read(walletRepositoryProvider), isNull);
  });
}
