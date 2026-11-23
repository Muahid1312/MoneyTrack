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
import 'package:moneytrack/features/explore/explore_screen.dart';

Future<ProviderContainer> _boot(
  WidgetTester tester, {
  bool seed = false,
  WalletSnapshot? wallets,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = InMemoryTransactionRepository(
    seed ? sampleData(DateTime.now()) : const [],
  );
  final container = ProviderContainer(
    overrides: [
      transactionRepositoryProvider.overrideWithValue(repo),
      if (wallets != null) walletsProvider.overrideWith((_) async => wallets),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
      projectsProvider.overrideWith(
        (ref) async => const ProjectSnapshot(
          projects: [],
          categories: [],
          allocations: [],
          transactions: [],
        ),
      ),
      reportDataProvider.overrideWith((ref) async {
        final all = ref.watch(transactionsProvider).valueOrNull ?? [];
        return ReportData(
          filter: ReportFilter(currency: ref.watch(currencyProvider)),
          transactions: all,
          allTransactions: all,
          wallets: [],
          positions: [],
          projects: [],
          projectCategories: [],
          allocations: [],
          debts: [],
          postings: [],
          goals: [],
        );
      }),
    ],
  );
  await container.read(transactionsProvider.future);
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MoneyTrackApp(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return container;
}

Future<void> _scrollTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(
      f,
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );

void main() {
  testWidgets('empty app shows empty states on every tab', (tester) async {
    await _boot(tester);
    expect(find.text('Calendar'),findsOneWidget);
    expect(find.text('No entries on this date.'),findsOneWidget);
    await tester.tap(find.byTooltip('Search all transactions'));await tester.pumpAndSettle();
    expect(find.text('No transactions yet'),findsOneWidget);
    await tester.pageBack();await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination,'More'));await tester.pumpAndSettle();
    final search = find.byType(TextField);
    final titles = {
      MoneyFeature.overview: 'Available cash',
      MoneyFeature.activity:'Search all transactions',
      MoneyFeature.wallets: 'Accounts',
      MoneyFeature.transfer: 'Transfer money',
      MoneyFeature.categories: 'Categories',
      MoneyFeature.add: 'Add expense',
      MoneyFeature.budget: 'Wallet budgets',
      MoneyFeature.monthly: 'Monthly spending limit',
      MoneyFeature.savings: 'Savings goals',
      MoneyFeature.recurring: 'Recurring & upcoming',
      MoneyFeature.debts: 'Debts & loans',
      MoneyFeature.upcoming: 'Upcoming payments',
      MoneyFeature.reminders: 'Local reminders',
      MoneyFeature.projects: 'Projects',
      MoneyFeature.groups: 'Groups & Trips',
      MoneyFeature.appearance:'Appearance',
      MoneyFeature.reports: 'Financial reports',
      MoneyFeature.currency: 'Reporting currency',
      MoneyFeature.backup: 'Encrypted backup & restore',
      MoneyFeature.security: 'App security',
      MoneyFeature.export: 'Data export',
      MoneyFeature.settings: 'Settings',
    };
    for (final feature in MoneyFeature.values) {
      await tester.enterText(search, feature.title);
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('feature-${feature.name}'));
      expect(tile, findsOneWidget, reason: feature.title);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      if (feature == MoneyFeature.insights) {
        expect(find.text('Trends and comparisons'),findsOneWidget);
        await tester.tap(find.widgetWithText(NavigationDestination,'More'));
      } else {
        expect(find.byType(ExploreScreen), findsNothing, reason: feature.title);
        expect(find.text(titles[feature]!), findsWidgets, reason: feature.name);
        expect(tester.takeException(), isNull, reason: feature.title);
        if (feature == MoneyFeature.savings)
          expect(find.text('New goal'), findsOneWidget);
        if (feature == MoneyFeature.projects)
          expect(find.text('New project'), findsOneWidget);
        if (feature == MoneyFeature.reports)
          expect(find.byTooltip('Refresh report'), findsOneWidget);
        if (feature == MoneyFeature.export)
          expect(find.text('Export to CSV'), findsOneWidget);
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      }
      await tester.pumpAndSettle();
    }
    for (final term in ['borrowed money', 'save money', 'business', 'monthly limit', 'backup']) {
      await tester.enterText(search, term);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets, reason: term);
    }
    await tester.tap(find.byTooltip('Pin Backup and restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Recently opened'), findsOneWidget);
  });

  testWidgets('save a decimal expense from the calendar and update the day and month', (
    tester,
  ) async {
    final container = await _boot(tester);
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);

    // Validation: empty amount
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('entry-amount')),'42.5');
    await tester.pumpAndSettle();
    expect(find.text('42.5'), findsOneWidget);

    // Validation: category required
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-category-food')));
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

  testWidgets(
    'Home wallet carries into a new expense and its activity history',
    (tester) async {
      const wallets = WalletSnapshot(
        [
          Wallet(
            id: 1,
            name: 'Bank',
            type: WalletType.bank,
            currency: AppCurrency.usd,
          ),
          Wallet(
            id: 2,
            name: 'Cash',
            type: WalletType.cash,
            currency: AppCurrency.afn,
          ),
        ],
        {1: 10000, 2: 2000000},
        [],
        reserved: {2: 500000},
      );
      final c = await _boot(tester, wallets: wallets);
      await tester.tap(find.widgetWithText(NavigationDestination,'More'));await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField),'available cash');await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feature-overview')));await tester.pumpAndSettle();
      await tester.tap(find.text('Bank · USD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash · AFN').last);
      await tester.pumpAndSettle();
      expect(find.text('15,000.00 ؋'), findsOneWidget);
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('entry-amount')),'5');
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final entry = c.read(allTransactionsProvider).single;
      expect(
        (entry.walletId, entry.currency, entry.amountMinor),
        (2, AppCurrency.afn, 500),
      );
      await tester.pageBack();await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination,'Transactions'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsWidgets);
    },
  );

  testWidgets(
    'find an older transaction and open its original receipt actions',
    (tester) async {
      await _boot(tester, seed: true);
      await tester.tap(find.byTooltip('Search all transactions'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Weekend trip');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekend trip').last);
      await tester.pumpAndSettle();
      expect(find.text('Receipts & documents'), findsOneWidget);
      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.text('Delete transaction'), findsOneWidget);
    },
  );

  testWidgets('seeded data renders statistics without errors', (tester) async {
    await _boot(tester, seed: true);
    await tester.tap(find.widgetWithText(NavigationDestination,'Statistics'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Trends and comparisons'));await tester.pumpAndSettle();await tester.tap(find.text('Trends and comparisons'));
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
