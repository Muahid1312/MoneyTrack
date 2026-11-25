import 'support/open_feature.dart';
import 'package:moneytrack/features/explore/explore_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/app/app_shell.dart';
import 'package:moneytrack/features/statistics/presentation/widgets/stat_charts.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:moneytrack/features/transactions/application/ledger_month.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fakes.dart';
import 'support/screen_capture.dart';

final clock = DateTime(2024, 2, 29, 11);
const usd = AppCurrency.usd, afn = AppCurrency.afn;
TransactionModel entry(
  int day,
  int minor,
  String note,
  String category, {
  int wallet = 1,
  AppCurrency currency = afn,
  bool income = false,
  int month = 2,
}) {
  final date = DateTime(2024, month, day, 10);
  return TransactionModel(
    walletId: wallet,
    currency: currency,
    type: income ? TransactionType.income : TransactionType.expense,
    amountMinor: minor,
    categoryId: category,
    note: note,
    occurredAt: date,
    createdAt: date,
    updatedAt: date,
  );
}

final entries = [
  entry(1, 2000000, 'February salary', 'salary', income: true),
  entry(4, 45000, 'Vegetables', 'groceries'),
  entry(12, 18500, 'Lunch', 'food'),
  entry(16, 30000, 'Taxi', 'transport'),
  entry(22, 25800, 'Market', 'groceries'),
  entry(29, 8500, 'Tea and bread', 'food'),
  entry(29, 125000, 'Translation', 'business', income: true),
  entry(29, 85000, 'Previous evening', 'food', wallet: 2, currency: usd),
  entry(1, 99000, 'March', 'other', month: 3),
];
final transfer = WalletTransfer(
  id: 3,
  sourceId: 1,
  destinationId: 2,
  sourceMinor: 70000,
  destinationMinor: 1000,
  rate: '0.0142857',
  sourceCurrency: afn,
  destinationCurrency: usd,
  occurredAt: DateTime(2024, 2, 29, 9),
);
const wallets = [
  Wallet(id: 1, name: 'Cash', type: WalletType.cash, currency: afn),
  Wallet(id: 2, name: 'Bank', type: WalletType.bank, currency: usd),
];
void main() {
  test(
    'calendar boundaries and transfer legs preserve month and original currency',
    () {
      expect(shiftLedgerMonth(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(
        shiftLedgerMonth(DateTime(2025, 3, 31), -1),
        DateTime(2025, 2, 28),
      );
      expect(
        shiftLedgerMonth(DateTime(2024, 12, 31), 1),
        DateTime(2025, 1, 31),
      );
      final m = LedgerMonth(clock, afn, entries, [transfer]);
      expect(
        (m.income, m.expense, m.days[29]!.records.length),
        (2125000, 127800, 3),
      );
      expect(LedgerMonth(clock, usd, entries, [transfer]).expense, 85000);
      expect(
        LedgerMonth(DateTime(2024, 3), afn, entries, [transfer]).expense,
        99000,
      );
      expect(
        LedgerMonth(DateTime(2024, 1), afn, entries, [transfer]).days,
        isEmpty,
      );
    },
  );

  testWidgets(
    'calendar, daily records, entry and statistics use the selected dates and accounts',
    (tester) async {
      SharedPreferences.setMockInitialValues({'currency':'AFN','monthly_budget_minor':220000});
      final prefs = await SharedPreferences.getInstance();
      final repo = InMemoryTransactionRepository(entries);
      final c = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repo),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepository(prefs),
          ),
          clockProvider.overrideWithValue(() => clock),
          walletsProvider.overrideWith(
            (_) async =>
                WalletSnapshot(wallets, {1: 2275000, 2: 45000}, [transfer],reserved:const {1:500000}),
          ),
        ],
      );
      final captureKey = GlobalKey();
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await loadCaptureFonts(tester);
      Future<void> capture(String name)=>captureView(tester,captureKey,name);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: const AppShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openFeature(tester, MoneyFeature.calendar);
      expect(find.text('February 2024'), findsOneWidget);
      expect(find.textContaining('Tea and bread'), findsOneWidget);
      expect(find.textContaining('Previous evening'), findsNothing);
      await capture('calendar');
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(find.text('Feb 2024'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Calendar')).maxLines, 1);
      await capture('calendar-narrow');
      tester.view.physicalSize = const Size(390, 780);
      await tester.pumpAndSettle();
      await tester.tap(find.text('February 2024'));await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog),findsOneWidget);await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'Daily').first);
      await tester.pumpAndSettle();
      await capture('daily');
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      final firstWeek = find.text('Feb 1 – Feb 3, 2024');
      expect(firstWeek, findsOneWidget);
      await capture('weekly');
      await tester.tap(firstWeek);
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      expect(find.textContaining('Previous evening'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('2024'),findsOneWidget);
      await capture('monthly');
      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();
      expect(find.text('2023'),findsOneWidget);
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Total'));
      await tester.pumpAndSettle();
      expect(find.text('922.00 ؋'),findsOneWidget);
      await capture('total');
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('day-${DateTime(2024, 2, 4).toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Vegetables'), findsOneWidget);
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Feb 4, 2024'), findsOneWidget);
      await capture('entry');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Income'));
      await tester.pumpAndSettle();
      await capture('entry-dark-income');
      await tester.tap(find.text('Cash · AFN').first);
      await tester.pumpAndSettle();
      expect(find.text('Choose account'), findsOneWidget);
      await capture('entry-accounts-dark');
      await tester.tap(find.byTooltip('Close accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Expense'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reuse an entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tea and bread'));
      await tester.pumpAndSettle();
      expect(find.text('85'), findsOneWidget);
      await tester.tap(find.text('Save expense'));
      await tester.tap(find.text('Save expense'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect((await repo.fetchAll()).length, entries.length + 1);
      expect(
        (await repo.fetchAll())
            .where((t) => t.note == 'Tea and bread' && t.occurredAt.day == 4)
            .length,
        1,
      );
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('January 2024'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openFeature(tester, MoneyFeature.insights);
      await capture('statistics');
      await tester.tap(find.widgetWithText(InkWell,'Income').hitTestable().last);
      await tester.pumpAndSettle();
      final donut = find.byType(ExpenseDonut);
      await tester.ensureVisible(donut);
      await tester.tapAt(tester.getCenter(donut) + const Offset(59, 0));
      await tester.pumpAndSettle();
      expect(find.text('February salary'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salary'));
      await tester.pumpAndSettle();
      expect(find.text('February salary'), findsWidgets);
      expect(find.textContaining('Tea and bread'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Accounts'));
      await tester.pumpAndSettle();
      await capture('accounts');
      expect(find.text('17,750.00 ؋'),findsWidgets);
      await tester.tap(find.byTooltip('Transfer money'));await tester.pumpAndSettle();await capture('transfer');
      await tester.pageBack();await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination,'More'));await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));await tester.pumpAndSettle();
      expect(find.text('Money Management'),findsOneWidget);
      expect(find.byKey(const ValueKey('feature-groups')).hitTestable(),findsOneWidget);
      await capture('more');
      await tester.enterText(find.byType(TextField),'monthly limit');await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feature-monthly')));await tester.pumpAndSettle();await capture('budget');
      await tester.pageBack();await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField),'appearance');await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feature-appearance')));await tester.pumpAndSettle();await capture('appearance');

      expect(tester.takeException(), isNull);
    },
  );
}
