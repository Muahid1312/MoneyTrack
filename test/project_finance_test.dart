import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/project.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/projects/domain/project_finance.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 11, 8);
Project _project({int? id, String name = 'House', ProjectType type = ProjectType.personal,
    AppCurrency currency = AppCurrency.usd, int? budget, int? contract,
    ProjectStatus status = ProjectStatus.active}) => Project(id: id, name: name,
  type: type, currency: currency, budgetMinor: budget, contractMinor: contract,
  startDate: _now, status: status, createdAt: _now, updatedAt: _now);
TransactionModel _entry({int? projectId, int? categoryId, int amount = 100,
    AppCurrency currency = AppCurrency.usd, String? rate, bool receipt = false,
    String? reference, TransactionType type = TransactionType.expense}) => TransactionModel(
  projectId: projectId, projectCategoryId: categoryId, projectRate: rate,
  clientReceipt: receipt, paymentReference: reference,
  currency: currency, type: type, amountMinor: amount,
  categoryId: type.isIncome ? 'business' : 'other',
  occurredAt: _now, createdAt: _now, updatedAt: _now);

const _v2Wallets = '''CREATE TABLE wallets (
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
  currency TEXT NOT NULL, opening_minor INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0)''';
const _v2Transactions = '''CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL CHECK(type IN ('income','expense')),
  amount_minor INTEGER NOT NULL CHECK(amount_minor>0), category_id TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '', occurred_at INTEGER NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, wallet_id INTEGER REFERENCES wallets(id), currency TEXT NOT NULL)''';
const _v2Transfers = '''CREATE TABLE transfers (
  id INTEGER PRIMARY KEY AUTOINCREMENT, source_id INTEGER NOT NULL REFERENCES wallets(id),
  destination_id INTEGER NOT NULL REFERENCES wallets(id), source_minor INTEGER NOT NULL,
  destination_minor INTEGER NOT NULL, source_currency TEXT NOT NULL,
  destination_currency TEXT NOT NULL, rate TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', occurred_at INTEGER NOT NULL)''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  group('Project ledger', () {
    late Directory dir;
    late AppDatabase db;
    late ProjectRepository projects;
    late SqfliteTransactionRepository transactions;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moneytrack-project-');
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/ledger.db');
      projects = ProjectRepository(db);
      transactions = SqfliteTransactionRepository(db);
    });
    tearDown(() async { await db.close(); await dir.delete(recursive: true); });
    Future<ProjectSummary> summary(int id) async {
      final data = await projects.fetch();
      return ProjectFinance.calculate(data.projects.firstWhere((p) => p.id == id),
        data.transactions, data.allocations, data.categories);
    }

    test('creates both types, edits details and restores the previous status', () async {
      final personal = await projects.save(_project(status: ProjectStatus.onHold));
      final business = await projects.save(_project(name: 'Client build', type: ProjectType.business, contract: 50000));
      expect((await projects.fetch()).categories.where((c) => c.projectId == personal).length, 5);
      await projects.addCategory(personal, 'Permits');
      await projects.save(_project(id: personal, name: 'House extension', budget: 30000, status: ProjectStatus.onHold));
      await projects.setArchived(personal, true);
      expect((await projects.fetch()).projects.firstWhere((p) => p.id == personal).isArchived, isTrue);
      await projects.setArchived(personal, false);
      final data = await projects.fetch();
      expect(data.projects.firstWhere((p) => p.id == personal).status, ProjectStatus.onHold);
      expect(data.projects.firstWhere((p) => p.id == personal).name, 'House extension');
      expect(data.projects.firstWhere((p) => p.id == business).contractMinor, 50000);
      await expectLater(projects.addCategory(personal, ' permits '), throwsA(isA<DatabaseException>()));
    });

    test('project labels never duplicate a transaction or change wallet amounts', () async {
      final first = await projects.save(_project());
      final second = await projects.save(_project(name: 'Trip', currency: AppCurrency.eur));
      final tx = await transactions.insert(_entry(amount: 1000));
      final before = (await WalletRepository(db).fetch()).balances[1];
      await transactions.update(tx.copyWith(projectId: () => first));
      expect((await summary(first)).expenses, 1000);
      await transactions.update(tx.copyWith(projectId: () => second, projectRate: () => '0.91'));
      expect((await summary(first)).expenses, 0);
      expect((await summary(second)).expenses, 910);
      expect((await WalletRepository(db).fetch()).balances[1], before);
      final assigned = (await transactions.fetchAll()).single;
      expect(assigned.id, tx.id);
      expect(assigned.amountMinor, 1000);
      expect(assigned.projectCurrency, AppCurrency.eur);
      await transactions.update(assigned.copyWith(projectId: () => null));
      final unassigned = (await transactions.fetchAll()).single;
      expect(unassigned.projectAmountMinor, isNull);
      expect(unassigned.projectRate, isNull);
      expect((await WalletRepository(db).fetch()).balances[1], before);
    });

    test('allocations and planned budgets are not income or wallet holdings', () async {
      final id = await projects.save(_project(budget: 1000));
      await projects.allocate(id, 1500, 'Reserved savings');
      expect((await WalletRepository(db).fetch()).balances[1], 0);
      expect(await transactions.fetchAll(), isEmpty);
      await transactions.insert(_entry(projectId: id, amount: 1200));
      final result = await summary(id);
      expect(result.expenses, 1200);
      expect(result.receipts, 0);
      expect(result.allocated, 1500);
      expect(result.availableAllocation, 300);
      expect(result.remainingBudget, -200);
      expect(result.overspent, isTrue);
      expect(result.usage, 1.2);
      expect(result.cashSurplus, -1200);
      await projects.removeAllocation((await projects.fetch()).allocations.single.id);
      expect((await summary(id)).availableAllocation, -1200);
      expect((await WalletRepository(db).fetch()).balances[1], -1200);
    });

    test('zero and missing budgets have distinct meanings', () async {
      final missing = await projects.save(_project());
      final zero = await projects.save(_project(name: 'Zero', budget: 0));
      await transactions.insert(_entry(projectId: zero));
      expect((await summary(missing)).remainingBudget, isNull);
      expect((await summary(missing)).usage, isNull);
      expect((await summary(zero)).remainingBudget, -100);
      expect((await summary(zero)).usage, isNull);
      expect((await summary(zero)).overspent, isTrue);
    });

    test('manual conversion is saved, rounded and retained on reopen and edits', () async {
      final id = await projects.save(_project(currency: AppCurrency.afn));
      await expectLater(transactions.insert(_entry(projectId: id)), throwsFormatException);
      final tx = await transactions.insert(_entry(projectId: id, rate: '70.125'));
      expect(tx.projectAmountMinor, 7013);
      expect(tx.amountMinor, 100);
      expect((await summary(id)).expenses, 7013);
      await transactions.update(tx.copyWith(note: 'Receipt checked'));
      expect((await summary(id)).expenses, 7013);
      await transactions.update(tx.copyWith(amountMinor: 200));
      expect((await summary(id)).expenses, 14025);
      await db.close();
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/ledger.db');
      projects = ProjectRepository(db);
      transactions = SqfliteTransactionRepository(db);
      final saved = (await transactions.fetchAll()).single;
      expect(saved.projectRate, '70.125');
      expect(saved.projectAmountMinor, 14025);
      expect((await WalletRepository(db).fetch()).balances[1], -200);
    });

    test('client payments reduce obligations once and surplus stays cash-based', () async {
      final id = await projects.save(_project(type: ProjectType.business, budget: 1000, contract: 5000));
      expect((await summary(id)).outstanding, 5000);
      final payment = await transactions.insert(_entry(projectId: id, amount: 3000,
        type: TransactionType.income, receipt: true, reference: ' Bank-001 '));
      expect(payment.paymentReference, 'bank-001');
      await expectLater(transactions.insert(_entry(projectId: id, amount: 3000,
        type: TransactionType.income, receipt: true, reference: 'BANK-001')), throwsA(isA<DatabaseException>()));
      final other = await projects.save(_project(name: 'Other client', type: ProjectType.business));
      await expectLater(transactions.insert(_entry(projectId: other, amount: 3000,
        type: TransactionType.income, receipt: true, reference: 'bank-001')), throwsA(isA<DatabaseException>()));
      await transactions.insert(_entry(projectId: id, amount: 500, type: TransactionType.income));
      await transactions.insert(_entry(projectId: id, amount: 1200));
      final result = await summary(id);
      expect(result.clientReceipts, 3000);
      expect(result.receipts, 3500);
      expect(result.outstanding, 2000);
      expect(result.cashSurplus, 2300);
      expect(result.monthly[DateTime(_now.year, _now.month)]!.surplus, 2300);
      expect((await transactions.fetchAll()).length, 3);
      expect((await WalletRepository(db).fetch()).balances[1], 2300);
      await transactions.delete(payment.id!);
      expect((await summary(id)).outstanding, 5000);
    });

    test('receipt updates cannot collide and overpayments are explicit', () async {
      final id = await projects.save(_project(type: ProjectType.business, contract: 100));
      final a = await transactions.insert(_entry(projectId: id, amount: 150,
        type: TransactionType.income, receipt: true, reference: 'one'));
      final b = await transactions.insert(_entry(projectId: id, amount: 50,
        type: TransactionType.income, receipt: true, reference: 'two'));
      await expectLater(transactions.update(b.copyWith(paymentReference: () => 'ONE')), throwsA(isA<DatabaseException>()));
      final result = await summary(id);
      expect(result.outstanding, 0);
      expect(result.overpayment, 100);
      expect(result.clientReceipts, 200);
      expect((await transactions.fetchAll()).firstWhere((t) => t.id == b.id).paymentReference, 'two');
      expect(a.id, isNot(b.id));
    });

    test('archive preserves history and prevents new postings until restored', () async {
      final id = await projects.save(_project());
      final tx = await transactions.insert(_entry(projectId: id));
      await projects.allocate(id, 200, 'Before archive');
      await projects.setArchived(id, true);
      expect((await summary(id)).expenses, 100);
      expect((await summary(id)).allocated, 200);
      await expectLater(transactions.insert(_entry(projectId: id)), throwsArgumentError);
      await expectLater(projects.allocate(id, 10, ''), throwsA(isA<DatabaseException>()));
      await projects.setArchived(id, false);
      await transactions.update(tx.copyWith(amountMinor: 150));
      expect((await summary(id)).expenses, 150);
    });

    test('foreign project/category references and illegal receipt types roll back', () async {
      final personal = await projects.save(_project());
      final business = await projects.save(_project(name: 'Work', type: ProjectType.business));
      final category = (await projects.fetch()).categories.firstWhere((c) => c.projectId == personal);
      await expectLater(transactions.insert(_entry(projectId: business, categoryId: category.id)), throwsA(isA<DatabaseException>()));
      await expectLater(transactions.insert(_entry(projectId: personal, type: TransactionType.income,
        receipt: true, reference: 'x')), throwsArgumentError);
      await expectLater(transactions.insert(_entry(projectId: business, receipt: true, reference: 'x')), throwsArgumentError);
      await expectLater(transactions.insert(_entry(projectId: 999)), throwsArgumentError);
      expect(await transactions.fetchAll(), isEmpty);
      expect((await WalletRepository(db).fetch()).balances[1], 0);
      await expectLater(projects.allocate(business, 10, ''), throwsA(isA<DatabaseException>()));
      await expectLater(projects.save(_project(id: personal, currency: AppCurrency.eur)), throwsA(isA<DatabaseException>()));
    });

    test('custom category and monthly reports use recorded project amounts', () async {
      final id = await projects.save(_project());
      await projects.addCategory(id, 'Permits');
      final category = (await projects.fetch()).categories.firstWhere((c) => c.name == 'Permits');
      final tx = await transactions.insert(_entry(projectId: id, categoryId: category.id, amount: 250));
      expect((await summary(id)).categoryExpenses['Permits'], 250);
      await transactions.update(tx.copyWith(amountMinor: 300));
      expect((await summary(id)).categoryExpenses['Permits'], 300);
      await transactions.delete(tx.id!);
      expect((await summary(id)).categoryExpenses, isEmpty);
    });
  });

  group('v2 migration compatibility', () {
    Future<Database> legacy(String path, {bool conflict = false}) async {
      final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 2,
        onCreate: (db, _) async {
          await db.execute(_v2Wallets); await db.execute(_v2Transactions); await db.execute(_v2Transfers);
          if (conflict) await db.execute('CREATE TABLE project_categories (legacy_marker TEXT)');
        }));
      await db.insert('wallets', {'id': 1, 'name': 'Cash', 'type': 'cash', 'currency': 'USD', 'opening_minor': 10000});
      await db.insert('wallets', {'id': 2, 'name': 'Bank', 'type': 'bank', 'currency': 'USD', 'opening_minor': 0});
      await db.insert('transactions', {'id': 17, 'type': 'income', 'amount_minor': 700,
        'category_id': 'salary', 'note': 'Keep me', 'occurred_at': 100, 'created_at': 100,
        'updated_at': 100, 'wallet_id': 1, 'currency': 'USD'});
      await db.insert('transfers', {'id': 9, 'source_id': 1, 'destination_id': 2,
        'source_minor': 100, 'destination_minor': 100, 'source_currency': 'USD',
        'destination_currency': 'USD', 'rate': '1', 'occurred_at': 100});
      return db;
    }
    test('preserves v2 wallet balances, transactions and transfers', () async {
      final dir = await Directory.systemTemp.createTemp('moneytrack-v2-');
      final path = '${dir.path}/legacy.db';
      final old = await legacy(path);
      await old.close();
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      try {
        expect(await db.db.getVersion(), AppDatabase.schemaVersion);
        final tx = (await SqfliteTransactionRepository(db).fetchAll()).single;
        expect(tx.id, 17); expect(tx.note, 'Keep me'); expect(tx.projectId, isNull);
        final wallets = await WalletRepository(db).fetch();
        expect(wallets.balances[1], 10600); expect(wallets.balances[2], 100);
        expect(wallets.transfers.single.id, 9);
        expect((await ProjectRepository(db).fetch()).projects, isEmpty);
        expect(await db.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally { await db.close(); await dir.delete(recursive: true); }
    });
    test('failed v3 migration leaves the v2 ledger and version intact', () async {
      final dir = await Directory.systemTemp.createTemp('moneytrack-v2-fail-');
      final path = '${dir.path}/legacy.db';
      final old = await legacy(path, conflict: true); await old.close();
      await expectLater(AppDatabase.open(factory: databaseFactoryFfi, path: path), throwsA(isA<DatabaseException>()));
      final raw = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(await raw.getVersion(), 2);
        expect((await raw.query('transactions')).single['id'], 17);
        expect((await raw.query('transfers')).single['id'], 9);
        expect(await raw.rawQuery("SELECT name FROM sqlite_master WHERE name='projects'"), isEmpty);
        expect((await raw.rawQuery('PRAGMA table_info(transactions)')).any((c) => c['name'] == 'project_id'), isFalse);
      } finally { await raw.close(); await dir.delete(recursive: true); }
    });
  });
}
