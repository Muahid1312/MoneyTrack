import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/features/dashboard/application/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moneytrack/app/app.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/core/widgets/transaction_tile.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/storage/access_guard.dart';
import 'package:moneytrack/data/storage/app_runtime.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'package:moneytrack/features/documents/application/document_service.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:moneytrack/features/projects/application/project_providers.dart';
import 'package:moneytrack/features/reports/application/report_service.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:moneytrack/features/transactions/application/transaction_filter.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:moneytrack/features/transactions/presentation/transactions_screen.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/core/utils/csv_exporter.dart';
import 'support/phase4_fixture.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  late Phase4Fixture f;
  setUp(() async { f=Phase4Fixture();await f.open(); });
  tearDown(() async { await f.close(); });

  test('undo restores canonical transaction ID, receipt metadata and bytes', () async {
    final repo=SqfliteTransactionRepository(f.database);
    final tx=await repo.insert(f.entry(120));
    final attachments=AttachmentRepository(f.runtime);
    await attachments.import(tx.id!,SelectedDocument('receipt.png',Phase4Fixture.image));
    final original=(await attachments.list(tx.id!)).single;
    await repo.delete(tx.id!);
    expect(await attachments.list(tx.id!),isEmpty);
    final restored=await repo.insert(tx);
    expect(restored.id,tx.id);
    expect((await attachments.list(restored.id!)).single,original);
    expect(await (await attachments.resolve(original))!.readAsBytes(),Phase4Fixture.image);
    await PortableSnapshot.validate(f.database.db);
  });

  test('receipt restore failure rolls back the transaction and can be retried', () async {
    final repo=SqfliteTransactionRepository(f.database);
    final tx=await repo.insert(f.entry(120));
    final attachments=AttachmentRepository(f.runtime);
    await attachments.import(tx.id!,SelectedDocument('receipt.png',Phase4Fixture.image));
    await repo.delete(tx.id!);
    await f.database.db.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON attachments BEGIN SELECT RAISE(ABORT,'Injected storage failure'); END");
    await expectLater(repo.insert(tx),throwsA(anything));
    expect((await repo.fetchAll()).where((t)=>t.id==tx.id),isEmpty);
    expect(await attachments.list(tx.id!),isEmpty);
    await f.database.db.execute('DROP TRIGGER fail_receipt');
    expect((await repo.insert(tx)).id,tx.id);
    expect(await attachments.list(tx.id!),hasLength(1));
  });

  test('recurring undo retains occurrence identity and reconciliation remains idempotent', () async {
    await f.seed();
    final repo=SqfliteTransactionRepository(f.database);
    final tx=(await repo.fetchAll()).firstWhere((t)=>t.recurringRuleId!=null);
    await repo.delete(tx.id!);
    expect((await f.database.db.query('recurring_occurrences',where:'transaction_id=?',whereArgs:[tx.id])),isEmpty);
    await repo.insert(tx);
    await PlanningRepository(f.database).reconcile(now:DateTime(2026,1,2));
    final rows=await f.database.db.query('transactions',where:'recurring_rule_id=? AND occurrence_date=?',whereArgs:[tx.recurringRuleId,tx.occurrenceDate]);
    expect(rows,hasLength(1));expect(rows.single['id'],tx.id);
    await PortableSnapshot.validate(f.database.db);
  });

  test('clear invalidates Undo and locked preferences cannot be changed', () async {
    final repo=SqfliteTransactionRepository(f.database);
    final c=ProviderContainer(overrides:[transactionRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);await c.read(transactionsProvider.future);
    final controller=c.read(transactionsProvider.notifier);
    final tx=await controller.add(f.entry(120));await controller.remove(tx.id!);await controller.clearAll();
    await expectLater(controller.restore(tx),throwsStateError);expect(await repo.fetchAll(),isEmpty);
    final settings=SettingsRepository(f.prefs);AccessGuard.setLocked(true);
    await expectLater(settings.save(settings.load().copyWith(userName:'Changed')),throwsStateError);
    expect(f.prefs.getString('user_name'),'Test user');
  });

  test('dashboard period changes preserve currency scope and lifetime cash', () async {
    final c=ProviderContainer(overrides:[
      clockProvider.overrideWithValue(()=>DateTime(2026,2,15)),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository(f.prefs)),
      transactionRepositoryProvider.overrideWithValue(InMemoryTransactionRepository([
        f.entry(120,at:DateTime(2026,1,15)), f.entry(230,at:DateTime(2026,2,15)),
        f.entry(999999,at:DateTime(2026,2,15)).copyWith(currency:AppCurrency.afn),
      ])),
    ]);
    addTearDown(c.dispose);await c.read(transactionsProvider.future);
    expect(c.read(dashboardSummaryProvider).month.expense,230);
    expect(c.read(dashboardSummaryProvider).balanceMinor,-350);
    c.read(dashboardMonthOffsetProvider.notifier).state=-1;
    expect(c.read(dashboardSummaryProvider).month.expense,120);
    expect(c.read(dashboardSummaryProvider).balanceMinor,-350);
  });

  test('CSV neutralizes whitespace-prefixed formulas without altering exact amounts', () {
    final csv=CsvExporter.build([f.entry(123,note:'  =HYPERLINK("malicious")')],'USD');
    expect(csv,contains("'  =HYPERLINK"));expect(csv,contains('1.23,-1.23,USD'));
  });

  testWidgets('one busy day builds only visible rows and search keeps the full history', (tester) async {
    final entries=[for(var i=0;i<5000;i++)f.entry(100,note:'Entry $i')];
    final c=ProviderContainer(overrides:[
      transactionRepositoryProvider.overrideWithValue(InMemoryTransactionRepository(entries)),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository(f.prefs)),
    ]);
    await c.read(transactionsProvider.future);
    tester.view.physicalSize=const Size(360,740);tester.view.devicePixelRatio=1;
    await tester.pumpWidget(UncontrolledProviderScope(container:c,child:MaterialApp(theme:AppTheme.light(),home:const Scaffold(body:TransactionsScreen()))));
    await tester.pumpAndSettle();
    expect(c.read(historyRowsProvider),hasLength(5001));
    expect(find.byType(TransactionTile).evaluate().length,lessThan(30));
    await tester.enterText(find.byType(TextField).first,'Entry 4999');
    await tester.pump(const Duration(milliseconds:300));await tester.pumpAndSettle();
    expect(c.read(filteredTransactionsProvider).count,1);expect(find.descendant(of:find.byType(TransactionTile), matching:find.text('Entry 4999')),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());c.dispose();
    tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();
  });

  for(final dark in [false,true]) {
    testWidgets('dashboard and navigation fit narrow screens with large text (${dark?'dark':'light'})', (tester) async {
      await tester.runAsync(() async { await f.seed(); });
      final c=ProviderContainer(overrides:[
        appRuntimeProvider.overrideWithValue(f.runtime),
        transactionRepositoryProvider.overrideWithValue(SqfliteTransactionRepository(f.database)),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(f.prefs)),
        walletRepositoryProvider.overrideWithValue(WalletRepository(f.database)),
        projectRepositoryProvider.overrideWithValue(ProjectRepository(f.database)),
        planningRepositoryProvider.overrideWithValue(PlanningRepository(f.database)),
      ]);
      await tester.runAsync(() async {
        await c.read(transactionsProvider.future);await c.read(walletsProvider.future);
        await c.read(projectsProvider.future);await c.read(planningProvider.future);
        await c.read(reportDataProvider.future);
        await c.read(settingsProvider.notifier).setThemeMode(dark?ThemeMode.dark:ThemeMode.light);
      });
      tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
      tester.platformDispatcher.textScaleFactorTestValue=1.6;
      await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MoneyTrackApp()));
      await tester.pumpAndSettle();expect(tester.takeException(),isNull);
      for(final tab in ['Projects','Reports','More','Home']) {
        await tester.tap(find.bySemanticsLabel(tab).last);await tester.pump();
        await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });await tester.pump(const Duration(milliseconds:500));
        expect(tester.takeException(),isNull,reason:tab);
      }
      await tester.pumpWidget(const SizedBox.shrink());c.dispose();
      tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
}
