import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/features/projects/application/project_providers.dart';
import 'package:moneytrack/features/reports/application/report_service.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moneytrack/app/app.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'support/fakes.dart';

Future<ProviderContainer> _boot(WidgetTester tester, {bool seed = false, WalletSnapshot? wallets}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = InMemoryTransactionRepository(seed ? sampleData(DateTime.now()) : const []);
  final container = ProviderContainer(overrides: [
    transactionRepositoryProvider.overrideWithValue(repo),
    if(wallets!=null)walletsProvider.overrideWith((_)async=>wallets),
    settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
    projectsProvider.overrideWith((ref) async => const ProjectSnapshot(projects: [], categories: [], allocations: [], transactions: [])),
    reportDataProvider.overrideWith((ref) async {
      final all=ref.watch(transactionsProvider).valueOrNull??[];
      return ReportData(filter: ReportFilter(currency:ref.watch(currencyProvider)), transactions:all, allTransactions:all,
        wallets:[],positions:[],projects:[],projectCategories:[],allocations:[],debts:[],postings:[],goals:[]);
    }),
  ]);
  await container.read(transactionsProvider.future);
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MoneyTrackApp()));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
    tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();
  });
  return container;
}

Future<void> _scrollTo(WidgetTester tester, Finder f) => tester.scrollUntilVisible(f, 300,
    scrollable: find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first);

void main() {
  testWidgets('empty app shows empty states on every tab', (tester) async {
    await _boot(tester);
    expect(find.text('Today'), findsOneWidget);
    await _scrollTo(tester, find.text('Start tracking'));
    expect(find.text('Start tracking'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Activity').last);
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Savings').last);
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('More').last);
    await tester.pumpAndSettle();
    for (final entry in [('Financial reports', 'Refresh report'), ('Projects', 'New project')]) {
      await _scrollTo(tester,find.text(entry.$1));
      await tester.ensureVisible(find.text(entry.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(entry.$1=='Financial reports' ? find.byTooltip(entry.$2) : find.text(entry.$2),findsOneWidget);
      await tester.pageBack();await tester.pumpAndSettle();
    }
    await _scrollTo(tester, find.text('Export to CSV'));
    expect(find.text('Export to CSV'), findsOneWidget);
  });

  testWidgets('add an expense via keypad updates dashboard and list', (tester) async {
    final container = await _boot(tester);
    await tester.tap(find.bySemanticsLabel('Add transaction').first);
    await tester.pumpAndSettle();
    expect(find.text('New transaction'), findsOneWidget);

    // Validation: empty amount
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);

    for (final k in ['4', '2', '.', '5']) {
      await tester.tap(find.bySemanticsLabel(k == '.' ? 'Decimal point' : k).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('42.5'), findsOneWidget);

    // Validation: category required
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    final all = container.read(allTransactionsProvider);
    expect(all.length, 1);
    expect(all.first.amountMinor, 4250);
    await _scrollTo(tester, find.text('Food & Dining'));
    expect(find.text('Food & Dining'), findsWidgets);
    expect(find.textContaining('−\$42.50'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Home wallet carries into a new expense and its activity history', (tester) async {
    const wallets = WalletSnapshot([
      Wallet(id:1,name:'Bank',type:WalletType.bank,currency:AppCurrency.usd),
      Wallet(id:2,name:'Cash',type:WalletType.cash,currency:AppCurrency.afn),
    ], {1:10000,2:2000000}, [], reserved:{2:500000});
    final c=await _boot(tester,wallets:wallets);
    await tester.tap(find.text('Bank · USD')); await tester.pumpAndSettle();
    await tester.tap(find.text('Cash · AFN').last); await tester.pumpAndSettle();
    expect(find.text('15,000.00 ؋'),findsOneWidget);
    await tester.tap(find.text('Add expense')); await tester.pumpAndSettle();
    expect(find.text('Add note'),findsNothing);
    await tester.tap(find.bySemanticsLabel('5').last);
    await tester.tap(find.text('All categories')); await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last); await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense')); await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    final entry=c.read(allTransactionsProvider).single;
    expect((entry.walletId,entry.currency,entry.amountMinor),(2,AppCurrency.afn,500));
    await tester.tap(find.bySemanticsLabel('Activity').last);await tester.pumpAndSettle();
    expect(find.text('Groceries'),findsWidgets);
  });

  testWidgets('seeded data renders statistics without errors', (tester) async {
    await _boot(tester, seed: true);
    await tester.tap(find.bySemanticsLabel('More').last);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Spending insights'));
    await tester.tap(find.text('Spending insights'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Expense breakdown'));
    expect(find.text('Expense breakdown'), findsOneWidget);
    await _scrollTo(tester, find.text('Monthly comparison'));
    await tester.drag(find.text('Monthly comparison'), const Offset(0, 4000));
    await tester.pumpAndSettle();
    for (final label in ['Last month', '3 months', '6 months', 'This year']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
