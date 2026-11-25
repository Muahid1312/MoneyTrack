import 'package:moneytrack/features/managed_funds/application/managed_fund_report.dart';
import 'package:moneytrack/features/reports/application/report_exporter.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/data/repositories/managed_fund_repository.dart';
import 'package:moneytrack/data/storage/access_guard.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'package:moneytrack/features/backup/application/backup_codec.dart';
import 'package:moneytrack/features/managed_funds/domain/managed_fund.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/phase4_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 11, 25, 10);
  late Phase4Fixture fixture;
  late ManagedFundRepository repo;
  var counter = 0;
  String key() => 'managed-${counter++}';
  Future<int> create(
    int amount, {
    String? request,
    AppCurrency currency = AppCurrency.afn,
  }) => repo.create(
    key: request ?? key(),
    name: 'Monthly groceries',
    provider: 'Father',
    currency: currency,
    initialMinor: amount,
    date: date,
    method: 'Cash',
    purpose: 'Family groceries',
  );
  Future<int> buy(
    int fund,
    int total,
    int cash, {
    String? request,
    int? correct,
  }) => repo.purchase(
    fund,
    key: request ?? key(),
    items: [PurchaseLine(name: 'Groceries', totalMinor: total)],
    date: date,
    method: 'Cash',
    cash: cash,
    correct: correct,
  );
  Future<ManagedLedger> ledger(int id) async => (await repo.get(id)).ledger;

  setUp(() async {
    fixture = Phase4Fixture();
    await fixture.open();
    repo = ManagedFundRepository(fixture.database);
  });
  tearDown(() => fixture.close());

  test(
    'grocery scenario A reaches 2,350 AFN and keeps personal and group records isolated',
    () async {
      await fixture.seed();
      final groups = GroupRepository(fixture.database);
      await groups.create(
        key: 'trip',
        name: 'Paghman',
        currency: AppCurrency.afn,
        date: date,
        members: ['Friend'],
      );
      final db = fixture.database.db;
      final before = {
        for (final name in [
          'transactions',
          'wallet_positions',
          'trip_groups',
          'trip_members',
          'trip_events',
        ])
          name: await db.query(name),
      };
      final fund = await create(1000000);
      final other = await create(12345, currency: AppCurrency.usd);
      final rice = PurchaseLine(
        name: 'Rice',
        quantityMilli: 25000,
        unit: 'kg',
        unitMinor: 7200,
      );
      final flour = PurchaseLine(
        name: 'Flour',
        quantityMilli: 50000,
        unit: 'kg',
        unitMinor: 3800,
      );
      final oil = PurchaseLine(
        name: 'Cooking oil',
        quantityMilli: 10000,
        unit: 'litres',
        unitMinor: 12000,
      );
      final first = await repo.purchase(
        fund,
        key: key(),
        items: [rice, flour, oil],
        cash: 490000,
        date: date,
        method: 'Cash',
      );
      await repo.purchase(
        fund,
        key: key(),
        items: [
          PurchaseLine(name: 'Meat', totalMinor: 175000),
          PurchaseLine(name: 'Vegetables', totalMinor: 65000),
          PurchaseLine(name: 'Transportation', totalMinor: 35000),
        ],
        cash: 275000,
        date: date,
        method: 'Cash',
      );
      final detail = await repo.get(fund);
      expect(detail.items[first]!.map((i) => i.total), [
        180000,
        190000,
        120000,
      ]);
      expect(
        (
          detail.ledger.received,
          detail.ledger.expenses,
          detail.ledger.cash,
          detail.ledger.netReturnable,
          detail.ledger.outstanding,
        ),
        (1000000, 765000, 235000, 235000, 0),
      );
      expect(detail.ledger.fund.status, FundStatus.active);
      expect(
        ((await ledger(other)).fund.currency, (await ledger(other)).cash),
        (AppCurrency.usd, 12345),
      );
      for (final e in before.entries) {
        expect(await db.query(e.key), e.value, reason: e.key);
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'scenario B tracks a mixed purchase and direct partial/full reimbursements',
    () async {
      final fund = await create(50000);
      final purchase = await buy(fund, 80000, 50000);
      final before = await ledger(fund);
      expect(
        (before.expenses, before.cash, before.outstanding, before.shortfall),
        (80000, 0, 30000, 30000),
      );
      final part = await repo.reimburse(
        fund,
        key: key(),
        purchase: purchase,
        amount: 10000,
        fromFund: false,
        date: date,
        provider: 'Father',
        method: 'Cash',
      );
      expect((await ledger(fund)).outstanding, 20000);
      await repo.reverse(
        fund,
        key: key(),
        target: part,
        date: date,
        reason: 'Wrong receipt',
      );
      expect((await ledger(fund)).outstanding, 30000);
      await repo.reimburse(
        fund,
        key: key(),
        purchase: purchase,
        amount: 30000,
        fromFund: false,
        date: date,
        provider: 'Father',
        method: 'Bank transfer',
      );
      final after = await ledger(fund);
      expect(
        (
          after.expenses,
          after.cash,
          after.outstanding,
          after.directReimbursements,
        ),
        (80000, 0, 0, 30000),
      );
      expect(await fixture.database.db.query('transactions'), isEmpty);
    },
  );

  test(
    'scenario C reserves the outstanding advance in the returnable calculation only once',
    () async {
      final fund = await create(1000000);
      await buy(fund, 700000, 700000);
      final personal = await buy(fund, 50000, 0);
      var l = await ledger(fund);
      expect(
        (l.cash, l.expenses, l.outstanding, l.netReturnable),
        (300000, 750000, 50000, 250000),
      );
      await repo.reimburse(
        fund,
        key: key(),
        purchase: personal,
        amount: 10000,
        fromFund: true,
        date: date,
        provider: 'Father',
        method: 'Cash',
      );
      l = await ledger(fund);
      expect((l.cash, l.outstanding, l.netReturnable), (290000, 40000, 250000));
      await repo.reimburse(
        fund,
        key: key(),
        purchase: personal,
        amount: 40000,
        fromFund: true,
        date: date,
        provider: 'Father',
        method: 'Cash',
      );
      l = await ledger(fund);
      expect(
        (
          l.cash,
          l.outstanding,
          l.netReturnable,
          l.expenses,
          l.cashSpent,
          l.fundReimbursements,
        ),
        (250000, 0, 250000, 750000, 700000, 50000),
      );
    },
  );

  test(
    'funding corrections and reversals are linked and enforce nonnegative cash atomically',
    () async {
      final fund = await create(100000);
      final original = (await ledger(fund)).events.single.id;
      await buy(fund, 85000, 85000);
      Future<int> correct(int amount) => repo.funding(
        fund,
        key: key(),
        amount: amount,
        provider: 'Father',
        date: date,
        method: 'Cash',
        correct: original,
      );
      await expectLater(correct(80000), throwsA(isA<FundRule>()));
      expect((await ledger(fund)).events.length, 2);
      final replacement = await correct(90000);
      final snapshot = await ledger(fund);
      expect((snapshot.received, snapshot.cash), (90000, 5000));
      expect(
        snapshot.events.singleWhere((e) => e.id == replacement).target,
        original,
      );
      expect(snapshot.reversed(original), isTrue);
      final added = await repo.funding(
        fund,
        key: key(),
        amount: 20000,
        provider: 'Father',
        date: date,
        method: 'Mobile money',
        note: 'Extra supplies',
      );
      await repo.reverse(
        fund,
        key: key(),
        target: added,
        date: date,
        reason: 'Duplicate deposit',
      );
      expect((await ledger(fund)).cash, 5000);
    },
  );

  test(
    'merchant refunds and purchase corrections preserve the net split and original history',
    () async {
      final fund = await create(100000);
      final purchase = await buy(fund, 80000, 50000);
      final refund = await repo.refund(
        fund,
        key: key(),
        purchase: purchase,
        cash: 10000,
        personal: 2000,
        date: date,
        merchant: 'Store',
        method: 'Cash',
      );
      var l = await ledger(fund);
      expect((l.cash, l.outstanding, l.expenses), (60000, 28000, 68000));
      await expectLater(
        buy(fund, 70000, 45000, correct: purchase),
        throwsA(isA<FundRule>()),
      );
      await expectLater(
        repo.refund(
          fund,
          key: key(),
          purchase: purchase,
          cash: 40001,
          personal: 0,
          date: date,
          merchant: 'Store',
          method: 'Cash',
        ),
        throwsA(isA<FundRule>()),
      );
      await repo.reverse(
        fund,
        key: key(),
        target: refund,
        date: date,
        reason: 'Merchant correction',
      );
      await buy(fund, 70000, 45000, correct: purchase);
      l = await ledger(fund);
      expect((l.cash, l.outstanding, l.expenses), (55000, 25000, 70000));
      expect(l.reversed(purchase), isTrue);
      expect(l.events.length, 6);
      expect((await repo.get(fund)).items[purchase]!.single.total, 80000);
    },
  );

  test(
    'same request returns original ID and concurrent overspending cannot create records',
    () async {
      final ids = await Future.wait([
        create(50000, request: 'create'),
        create(50000, request: 'create'),
      ]);
      expect(ids.toSet(), hasLength(1));
      final fund = ids.first;
      final purchases = await Future.wait([
        buy(fund, 40000, 40000, request: 'purchase'),
        buy(fund, 40000, 40000, request: 'purchase'),
      ]);
      expect(purchases.toSet(), hasLength(1));
      await expectLater(
        buy(fund, 40000, 39000, request: 'purchase'),
        throwsA(isA<FundRule>()),
      );
      final outcomes = await Future.wait([
        for (final _ in [1, 2])
          buy(fund, 10000, 10000).then<bool>(
            (_) => true,
            onError: (Object e) {
              expect(e, isA<FundRule>());
              return false;
            },
          ),
      ]);
      expect(outcomes.where((x) => x), hasLength(1));
      expect((await ledger(fund)).cash, 0);
      expect((await ledger(fund)).events.length, 3);
    },
  );

  test(
    'rejects cross-fund targets, excessive reimbursement, invalid splits and locked writes',
    () async {
      final first = await create(50000);
      final second = await create(50000);
      final event = await buy(first, 50000, 20000);
      Future<int> reimburse(int fund, int amount) => repo.reimburse(
        fund,
        key: key(),
        purchase: event,
        amount: amount,
        fromFund: false,
        date: date,
        provider: 'Father',
        method: 'Cash',
      );
      await expectLater(reimburse(second, 1000), throwsA(isA<FundRule>()));
      await expectLater(reimburse(first, 30001), throwsA(isA<FundRule>()));
      await expectLater(
        Future.sync(() => buy(first, 1000, 1500)),
        throwsA(isA<FundRule>()),
      );
      AccessGuard.maintenance = true;
      await expectLater(buy(second, 1000, 1000), throwsStateError);
      expect((await ledger(second)).events, hasLength(1));
    },
  );

  test(
    'prices multiply as fixed-point values and round once without overflow',
    () {
      expect(PurchaseLine.parseQuantity('0.005'), 5);
      expect(PurchaseLine.parseQuantity('1.1111'), isNull);
      expect(
        PurchaseLine(
          name: 'Rice',
          quantityMilli: 1250,
          unit: 'kg',
          unitMinor: 101,
        ).total,
        126,
      );
      expect(
        PurchaseLine(
          name: 'Thread',
          quantityMilli: 500,
          unit: 'm',
          unitMinor: 1,
        ).total,
        1,
      );
      expect(
        () => PurchaseLine(
          name: 'Bulk',
          quantityMilli: 999999999,
          unit: 'kg',
          unitMinor: AppInfo.maxAmountMinor,
        ),
        throwsA(isA<FundRule>()),
      );
    },
  );

  test(
    'receipt replacement, deduplication, encrypted restore and corrupt-stage rejection',
    () async {
      final fund = await create(80000);
      final event = await buy(fund, 75000, 60000);
      final image = Phase4Fixture.image;
      final different = Uint8List.fromList([...image, 0]);
      await repo.saveReceipt(fund, event, name: 'Original.png', bytes: image);
      await repo.saveReceipt(fund, event, name: 'Same.png', bytes: image);
      expect(await repo.receipts(fund, event), hasLength(1));
      final id = (await repo.receipts(fund, event)).single.id;
      await repo.saveReceipt(
        fund,
        event,
        name: 'Replacement.png',
        bytes: different,
        replace: id,
      );
      expect(await repo.receipt(fund, event, id), different);
      final snapshot = await PortableSnapshot.capture(
        fixture.database,
        fixture.store.receipts,
        fixture.prefs,
      );
      final encrypted = await BackupCodec.encrypt(
        snapshot,
        'managed fund test passphrase',
      );
      final restored = await BackupCodec.decrypt(
        encrypted,
        'managed fund test passphrase',
      );
      final stage = await fixture.store.prepare(restored);
      final copy = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: p.join(fixture.store.directory(stage.id).path, 'moneytrack.db'),
      );
      try {
        final restoredRepo = ManagedFundRepository(copy);
        final restoredLedger = (await restoredRepo.get(fund)).ledger;
        expect(
          (
            restoredLedger.cash,
            restoredLedger.expenses,
            restoredLedger.outstanding,
          ),
          (20000, 75000, 15000),
        );
        expect(await restoredRepo.receipt(fund, event, id), different);
        final recovered = await restoredRepo.create(
          key: 'new-fund-after-restore',
          name: 'Other funds',
          provider: 'Mother',
          currency: AppCurrency.afn,
          initialMinor: 1000,
          date: date,
          method: 'Cash',
        );
        expect(recovered, greaterThan(fund));
      } finally {
        await copy.close();
        await fixture.store.discard(stage.id);
      }
      final data = jsonDecode(jsonEncode(restored)) as Map<String, dynamic>;
      data['tables']['managed_receipts'][0]['sha256'] = '0' * 64;
      await expectLater(fixture.store.prepare(data), throwsA(isA<FundRule>()));
      expect(await repo.receipt(fund, event, id), different);
      await repo.removeReceipt(fund, event, id);
      expect(await repo.receipts(fund, event), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'schema 7 restore preserves populated group and personal data',
    () async {
      await fixture.seed();
      await GroupRepository(fixture.database).create(
        key: 'shared',
        name: 'Household party',
        currency: AppCurrency.afn,
        date: date,
        members: ['Friend'],
      );
      final snapshot = await PortableSnapshot.capture(
        fixture.database,
        fixture.store.receipts,
        fixture.prefs,
      );
      final tables = snapshot['tables'] as Map;
      tables.removeWhere((k, v) => k.toString().startsWith('managed_'));
      snapshot['schema'] = 7;
      final stage = await fixture.store.prepare(snapshot);
      final copy = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: p.join(fixture.store.directory(stage.id).path, 'moneytrack.db'),
      );
      try {
        expect(await copy.db.getVersion(), 8);
        expect(await copy.db.query('transactions'), tables['transactions']);
        expect(await copy.db.query('trip_groups'), tables['trip_groups']);
        expect(await copy.db.query('managed_funds'), isEmpty);
      } finally {
        await copy.close();
        await fixture.store.discard(stage.id);
      }
    },
  );
  test(
    'managed activity exports the exact item ledger in English and Dari',
    () async {
      final fund = await repo.create(
        key: key(),
        name: 'مواد غذایی',
        provider: 'پدر',
        currency: AppCurrency.afn,
        initialMinor: 1000000,
        date: date,
        method: 'Cash',
      );
      await repo.purchase(
        fund,
        key: key(),
        date: date,
        method: 'Cash',
        cash: 180000,
        items: [
          PurchaseLine(
            name: 'برنج',
            quantityMilli: 25000,
            unit: 'کیلو',
            unitMinor: 7200,
          ),
        ],
      );
      final detail = await repo.get(fund);
      for (final dari in [false, true]) {
        final report = managedFundReport(detail, dari: dari);
        expect(report.rightToLeft, dari);
        expect(report.scope, contains('8200.00 AFN'));
        expect(report.rows.last, contains('1800.00 AFN'));
        expect(ReportExporter.csv(report), contains('برنج'));
        final pdf = await ReportExporter.pdf(report);
        expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      }
    },
  );
}
