import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/database/group_migration.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/data/storage/access_guard.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'package:moneytrack/features/backup/application/backup_codec.dart';
import 'package:moneytrack/features/groups/application/group_report.dart';
import 'package:moneytrack/features/groups/domain/group_fund.dart';
import 'package:moneytrack/features/reports/application/report_exporter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/phase4_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 4, 2);
  late Phase4Fixture fixture;
  late GroupRepository repo;
  late int group;
  var n = 0;
  Future<void> create(List<String> members, {int expected = 30000}) async {
    group = await repo.create(
      key: 'trip',
      name: 'Paghman trip',
      currency: AppCurrency.afn,
      date: at,
      members: members,
      expected: expected,
    );
  }

  TripEntry entry(
    EntryKind k, {
    int a = 0,
    int? m,
    int? related,
    String label = '',
    String note = '',
    String cat = 'Food',
  }) => TripEntry(
    kind: k,
    at: at,
    amount: a,
    member: m,
    related: related,
    label: label,
    category: k.purchase ? cat : '',
    method: k == EntryKind.contribution ? 'Cash' : '',
    note: note,
  );
  Future<int> post(
    EntryKind k, {
    int a = 0,
    int? m,
    int? link,
    String item = '',
    String note = '',
  }) => repo.post(
    group,
    'event${++n}',
    entry(k, a: a, m: m, related: link, label: item, note: note),
  );
  Future<void> plan() async {
    final g = await repo.get(group);
    await repo.post(
      group,
      'plan${++n}',
      TripEntry(kind: EntryKind.confirm, at: at, allocation: g.preview()),
      revision: g.revision,
    );
  }

  setUp(() async {
    fixture = Phase4Fixture();
    await fixture.open();
    repo = GroupRepository(fixture.database);
    n = 0;
  });
  tearDown(() async => fixture.close());

  test(
    'Paghman end to end, ten actual refunds, final PDF, independent wallet totals',
    () async {
      final before = await fixture.database.db.query('wallet_positions');
      await create(List.generate(10, (i) => 'Friend ${i + 1}'));
      var g = await repo.get(group);
      expect(
        [g.expected, g.collected, g.cash, g.stage],
        [300000, 0, 0, TripStage.planning],
      );
      for (final m in g.roster) {
        await post(EntryKind.contribution, a: 30000, m: m.id);
      }
      for (final i in [
        ('Transportation', 70000),
        ('Food', 90000),
        ('Drinks', 25000),
        ('Fruits', 30000),
        ('Snacks', 20000),
      ]) {
        await repo.post(
          group,
          'buy-${i.$1}',
          entry(EntryKind.cashExpense, a: i.$2, m: 1, label: i.$1, cat: i.$1),
        );
      }
      g = await repo.get(group);
      expect(
        [g.collected, g.outstanding, g.spent, g.cash, g.surplus],
        [300000, 0, 235000, 65000, 65000],
      );
      expect(g.preview().values, everyElement(6500));
      await plan();
      g = await repo.get(group);
      expect([g.refunded, g.cash, g.stage], [0, 65000, TripStage.settlement]);
      await expectLater(post(EntryKind.complete), throwsA(isA<FundError>()));
      for (final m in g.roster) {
        await post(EntryKind.refund, a: 6500, m: m.id);
      }
      await post(EntryKind.complete);
      g = await repo.get(group);
      expect([g.stage, g.cash, g.refunded], [TripStage.completed, 0, 65000]);
      expect(await fixture.database.db.query('wallet_positions'), before);
      expect(await fixture.database.db.query('transactions'), isEmpty);
      final report = GroupReport(g);
      expect(report.summary, contains('Completed'));
      expect(report.document.rows.expand((r) => r), contains('Refund paid'));
      expect(
        (await ReportExporter.pdf(report.document)).length,
        greaterThan(1000),
      );
    },
  );

  test(
    'unequal contributions and exact deterministic largest remainders even with large products',
    () async {
      await create(['Ahmad', 'Mahmood', 'Omid', 'Farid']);
      for (final v in {1: 30000, 2: 30000, 3: 50000, 4: 20000}.entries) {
        await post(EntryKind.contribution, m: v.key, a: v.value);
      }
      await post(EntryKind.cashExpense, a: 90000, m: 1, item: 'Coach');
      expect((await repo.get(group)).preview(), {
        1: 9231,
        2: 9231,
        3: 15384,
        4: 6154,
      });
      expect(proportionalRefunds({4: 1, 3: 1, 2: 1, 1: 1}, 2), {
        1: 1,
        2: 1,
        3: 0,
        4: 0,
      });
      final weights = {1: 99999999999, 2: 99999999998, 3: 1, 4: 0};
      final large = proportionalRefunds(weights, 98765432101);
      expect(large.values.fold<int>(0, (n, v) => n + v), 98765432101);
      expect(large.containsKey(4), isFalse);
      expect(quantityCost(1250, 2500), 3125);
      expect(quantityCost(1500, 1), 2);
    },
  );

  test(
    'add, edit, safe removal and partial/multiple/additional/voided contributions',
    () async {
      await create(['Ahmad']);
      await repo.member(group, name: 'Mahmood', expected: 20000);
      await repo.member(group, id: 2, name: 'Omid', expected: 40000);
      final first = await post(EntryKind.contribution, m: 2, a: 8000);
      await post(EntryKind.contribution, m: 2, a: 12000);
      var g = await repo.get(group);
      expect(g.memberDue(g.members[2]!), 20000);
      await post(
        EntryKind.reverse,
        link: first,
        note: 'Recorded twice on paper',
      );
      await expectLater(
        post(EntryKind.reverse, link: first, note: 'again'),
        throwsA(isA<FundError>()),
      );
      await post(EntryKind.contribution, m: 2, a: 35000);
      g = await repo.get(group);
      expect(
        [g.net[2], g.outstanding, g.members[2]!.name],
        [47000, 30000, 'Omid'],
      );
      await expectLater(
        repo.member(group, id: 2, name: 'Omid', expected: 0, remove: true),
        throwsA(isA<FundError>()),
      );
      await repo.member(
        group,
        id: 1,
        name: 'Ahmad',
        expected: 30000,
        remove: true,
      );
      expect((await repo.get(group)).roster.single.id, 2);
      await expectLater(
        post(EntryKind.contribution, m: 1, a: 1),
        throwsA(isA<FundError>()),
      );
    },
  );

  test(
    'personal purchase, unpaid bill, partial reimbursements and deficit handling',
    () async {
      await create(['Ada', 'Ali']);
      final purchase = await post(
        EntryKind.memberExpense,
        a: 6000,
        m: 2,
        item: 'Food',
      );
      final bill = await post(EntryKind.liability, a: 2000, item: 'Bus');
      var g = await repo.get(group);
      expect([g.cash, g.spent, g.surplus], [0, 8000, -8000]);
      expect(g.preview, throwsA(isA<FundError>()));
      await expectLater(
        post(EntryKind.cashExpense, m: 1, a: 1, item: 'Tea'),
        throwsA(isA<FundError>()),
      );
      await post(EntryKind.contribution, a: 10000, m: 1);
      await post(EntryKind.reimburse, a: 1500, m: 2, link: purchase);
      g = await repo.get(group);
      expect(
        [g.cash, g.surplus, g.reimbursed, g.owed(EntryKind.memberExpense)],
        [8500, 2000, 1500, 4500],
      );
      await expectLater(
        post(EntryKind.reimburse, a: 4501, m: 2, link: purchase),
        throwsA(isA<FundError>()),
      );
      await plan();
      await post(EntryKind.refund, m: 1, a: 2000);
      await expectLater(post(EntryKind.complete), throwsA(isA<FundError>()));
      await post(EntryKind.payBill, link: bill, a: 2000);
      await post(EntryKind.reimburse, m: 2, link: purchase, a: 4500);
      await post(EntryKind.complete);
      expect((await repo.get(group)).cash, 0);
    },
  );

  test(
    'retries, concurrent payouts, frozen plan, partial payment, explicit reopening and recovery',
    () async {
      await create(['A', 'B']);
      final first = await post(EntryKind.contribution, m: 1, a: 10000);
      final second = await post(EntryKind.contribution, m: 2, a: 10000);
      final original = await repo.get(group);
      await post(EntryKind.cashExpense, m: 1, a: 10000, item: 'Lunch');
      await expectLater(
        repo.post(
          group,
          'stale',
          TripEntry(
            kind: EntryKind.confirm,
            at: at,
            allocation: original.preview(),
          ),
          revision: original.revision,
        ),
        throwsA(isA<FundError>()),
      );
      await plan();
      final payout = entry(EntryKind.refund, m: 1, a: 4000);
      final ids = await Future.wait([
        repo.post(group, 'payment-1', payout),
        repo.post(group, 'payment-1', payout),
      ]);
      expect(ids.toSet(), hasLength(1));
      await expectLater(
        repo.post(group, 'payment-1', entry(EntryKind.refund, m: 1, a: 100)),
        throwsA(isA<FundError>()),
      );
      await expectLater(
        post(EntryKind.refund, m: 1, a: 1001),
        throwsA(isA<FundError>()),
      );
      var g = await repo.get(group);
      expect([g.cash, g.dueRefund(1)], [6000, 1000]);
      await expectLater(
        post(EntryKind.reverse, link: first, note: 'error'),
        throwsA(isA<FundError>()),
      );
      await post(EntryKind.reopen, note: 'Correct duplicated collection');
      await post(
        EntryKind.reverse,
        link: first,
        note: 'Wrong account on paper',
      );
      g = await repo.get(group);
      expect(g.preview, throwsA(isA<FundError>()));
      expect(
        g.events.values
            .where((e) => e.kind == EntryKind.confirm)
            .single
            .allocation,
        {1: 5000, 2: 5000},
      );
      await post(
        EntryKind.returnRefund,
        m: 1,
        a: 4000,
        note: 'Cash counted back',
      );
      await plan();
      await post(EntryKind.complete);
      await post(EntryKind.reopen, note: 'Review receipt');
      g = await repo.get(group);
      expect(g.reversed, {first});
      expect(g.events.containsKey(second), isTrue);
      expect(g.refunded, 0);
    },
  );

  test(
    'counting physical cash records discrepancies without a posting and protects settlement',
    () async {
      await create(['A']);
      await post(EntryKind.contribution, m: 1, a: 500);
      await post(EntryKind.cashCount, a: 450);
      var g = await repo.get(group);
      expect(g.countVariances.values.last, -50);
      expect(g.cash, 500);
      expect(g.preview, throwsA(isA<FundError>()));
      await post(EntryKind.cashCount, a: 500);
      await plan();
      await post(EntryKind.cashCount, a: 480);
      await expectLater(
        post(EntryKind.refund, a: 500, m: 1),
        throwsA(isA<FundError>()),
      );
      await post(EntryKind.cashCount, a: 500);
      await post(EntryKind.refund, a: 500, m: 1);
      await post(EntryKind.cashCount, a: 0);
      await post(EntryKind.complete);
      g = await repo.get(group);
      expect(g.countVariances.values, [-50, 0, -20, 0, 0]);
      expect(g.cash, 0);
    },
  );

  test(
    'revised plan credits previous payments and retains immutable confirmations',
    () async {
      await create(['A', 'B']);
      await post(EntryKind.contribution, a: 10000, m: 1);
      await post(EntryKind.contribution, a: 10000, m: 2);
      await plan();
      await post(EntryKind.refund, a: 2000, m: 1);
      await post(EntryKind.reopen, note: 'Add final receipt');
      await post(EntryKind.cashExpense, a: 5000, m: 1, item: 'Fuel');
      final before = await repo.get(group);
      expect(before.surplus, 13000);
      expect(before.preview(), {1: 7500, 2: 7500});
      await plan();
      var g = await repo.get(group);
      expect([g.dueRefund(1), g.dueRefund(2), g.cash], [5500, 7500, 13000]);
      expect(
        g.events.values
            .where((e) => e.kind == EntryKind.confirm)
            .map((e) => e.allocation),
        [
          {1: 10000, 2: 10000},
          {1: 7500, 2: 7500},
        ],
      );
      await expectLater(
        fixture.database.db.delete(
          'trip_events',
          where: 'id=?',
          whereArgs: [g.revision],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await post(EntryKind.refund, a: 5500, m: 1);
      await post(EntryKind.refund, a: 7500, m: 2);
      await post(EntryKind.complete);
      g = await repo.get(group);
      expect(g.refunded, 15000);
    },
  );

  test('empty projects, cancelled reconciliation and zero surplus', () async {
    await create(['Friend']);
    expect((await repo.get(group)).preview(), isEmpty);
    await post(EntryKind.cancel, note: 'Weather');
    await plan();
    await post(EntryKind.complete);
    await post(EntryKind.reopen, note: 'Trip rescheduled');
    await post(EntryKind.contribution, m: 1, a: 100);
    await post(EntryKind.cancel, note: 'Cancelled');
    await plan();
    await post(EntryKind.refund, m: 1, a: 100);
    await post(EntryKind.complete);
    expect((await repo.get(group)).cash, 0);
  });

  test(
    'purchase edits are atomic and original audit and photos survive restart and encrypted restore',
    () async {
      await fixture.seed();
      final personal = await fixture.database.db.query(
        'transactions',
        orderBy: 'id',
      );
      group = await repo.create(
        key: 'trip',
        name: 'Paghman trip',
        currency: AppCurrency.afn,
        date: at,
        members: ['A'],
        image: Phase4Fixture.image,
      );
      await post(EntryKind.contribution, m: 1, a: 10000);
      final old = await repo.post(
        group,
        'purchase',
        TripEntry(
          kind: EntryKind.cashExpense,
          member: 1,
          at: at,
          amount: 2500,
          label: 'Water',
          category: 'Drinks',
          quantity: 10000,
          unit: 250,
        ),
        image: Phase4Fixture.image,
      );
      final reversal = entry(
        EntryKind.reverse,
        related: old,
        note: 'Correct shop receipt',
      );
      await expectLater(
        repo.post(
          group,
          'invalid edit',
          reversal,
          replacement: entry(
            EntryKind.cashExpense,
            a: 10001,
            m: 1,
            label: 'Large',
          ),
        ),
        throwsA(isA<FundError>()),
      );
      expect((await repo.get(group)).reversed, isEmpty);
      await repo.post(
        group,
        'edit',
        reversal,
        replacement: entry(
          EntryKind.cashExpense,
          a: 2000,
          m: 1,
          label: 'Water',
        ),
      );
      final corrected = (await repo.get(group)).revision;
      await plan();
      await post(EntryKind.refund, m: 1, a: 1000);
      final path = fixture.database.db.path;
      await fixture.database.close();
      fixture.database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      repo = GroupRepository(fixture.database);
      final g = await repo.get(group);
      expect([g.cash, g.spent, g.dueRefund(1)], [7000, 2000, 7000]);
      expect(g.reversed, {old});
      final snapshot = await PortableSnapshot.capture(
        fixture.database,
        fixture.store.receipts,
        fixture.prefs,
      );
      final encrypted = await BackupCodec.encrypt(
        snapshot,
        'groups safe passphrase',
      );
      final decoded = await BackupCodec.decrypt(
        encrypted,
        'groups safe passphrase',
      );
      final stage = await fixture.store.prepare(decoded);
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${fixture.store.directory(stage.id).path}/moneytrack.db',
      );
      try {
        final restored = GroupRepository(db);
        final again = await restored.get(group);
        expect(again.events.keys, g.events.keys);
        expect(again.allocation, g.allocation);
        expect(again.cash, g.cash);
        expect(await restored.image(group, corrected), Phase4Fixture.image);
        expect(await restored.image(group, null), Phase4Fixture.image);
        expect(await db.db.query('transactions', orderBy: 'id'), personal);
      } finally {
        await db.close();
        await fixture.store.discard(stage.id);
      }
      final corrupt = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
      (corrupt['tables']['trip_events'] as List).last['amount_minor'] = 10001;
      await expectLater(
        fixture.store.prepare(corrupt),
        throwsA(isA<FundError>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'schema 6 backups restore with empty groups and unchanged personal records',
    () async {
      await fixture.seed();
      final data = await PortableSnapshot.capture(
        fixture.database,
        fixture.store.receipts,
        fixture.prefs,
      );
      data['schema'] = 6;
      for (final t in groupTables) {
        (data['tables'] as Map).remove(t);
      }
      final stage = await fixture.store.prepare(data);
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${fixture.store.directory(stage.id).path}/moneytrack.db',
      );
      try {
        expect(await GroupRepository(db).list(), isEmpty);
        expect(
          await db.db.query('transactions', orderBy: 'id'),
          data['tables']['transactions'],
        );
      } finally {
        await db.close();
        await fixture.store.discard(stage.id);
      }
    },
  );
  test(
    'independent groups, currency precision, lock and foreign member protection',
    () async {
      await create(['A']);
      final other = await repo.create(
        key: 'other',
        name: 'Second',
        currency: AppCurrency.jpy,
        date: at,
        members: ['B'],
      );
      final foreign = (await repo.get(other)).roster.single.id;
      await expectLater(
        post(EntryKind.contribution, m: foreign, a: 100),
        throwsA(isA<FundError>()),
      );
      await post(EntryKind.contribution, m: 1, a: 100);
      expect((await repo.get(other)).cash, 0);
      AccessGuard.locked = true;
      await expectLater(
        post(EntryKind.contribution, m: 1, a: 1),
        throwsA(isA<StateError>()),
      );
    },
  );
}
