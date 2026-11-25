import 'package:moneytrack/features/explore/explore_screen.dart';
import 'support/open_feature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/app/app_shell.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/core/utils/date_utils.dart';
import 'package:moneytrack/data/models/planning.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/data/storage/app_runtime.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:moneytrack/features/statistics/domain/cash_history.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'support/phase4_fixture.dart';
import 'support/fakes.dart';
import 'package:moneytrack/features/transactions/application/transaction_filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'a wallet filter isolates two wallets even when their currency matches',
    () {
      final entry = sampleData(DateTime(2026, 5)).first;
      final bank = entry.copyWith(walletId: 1);
      final cash = entry.copyWith(walletId: 2);
      final filter = TransactionFilter(
        walletId: 2,
        categoryIds: {entry.categoryId},
      );
      expect(filter.matches(bank, null), isFalse);
      expect(filter.matches(cash, null), isTrue);
      expect(filter.copyWith(walletId: () => null).matches(bank, null), isTrue);
    },
  );

  test(
    'cash history uses dated original-currency movements, including principal and transfers',
    () {
      final day = DateTime(2026, 2, 1);
      final tx = sampleData(
        day,
      ).first.copyWith(walletId: 1, amountMinor: 100, occurredAt: day);
      final other = tx.copyWith(
        walletId: 2,
        currency: AppCurrency.afn,
        amountMinor: 900000,
      );
      final transfer = WalletTransfer(
        sourceId: 1,
        destinationId: 2,
        sourceMinor: 50,
        destinationMinor: 3500,
        rate: '70',
        sourceCurrency: AppCurrency.usd,
        destinationCurrency: AppCurrency.afn,
        occurredAt: day,
      );
      DebtPosting posting(int amount, bool voided) => DebtPosting({
        'wallet_minor': amount,
        'direction': 1,
        'currency': 'USD',
        'voided': voided ? 1 : 0,
        'occurred_at': day.millisecondsSinceEpoch,
      });
      final snapshot = WalletSnapshot(
        const [
          Wallet(
            id: 1,
            name: 'Bank',
            type: WalletType.bank,
            currency: AppCurrency.usd,
            openingMinor: 500,
          ),
          Wallet(
            id: 2,
            name: 'Cash',
            type: WalletType.cash,
            currency: AppCurrency.afn,
            openingMinor: 1000,
          ),
        ],
        const {},
        [transfer],
        reserved: const {1: 200},
        debtPostings: [posting(30, false), posting(40, true)],
      );
      final entries = [
        tx,
        other,
        tx.copyWith(amountMinor: 999999, occurredAt: DateTime(2026, 2, 4)),
      ];
      final span = DateSpan(DateTime(2026, 1, 31), DateTime(2026, 3));
      final usd = cashHistory(snapshot, entries, AppCurrency.usd, span, day);
      expect(usd.map((r) => r.minor), [500, 580]);
      expect(
        cashHistory(snapshot, entries, AppCurrency.afn, span, day).last.minor,
        904500,
      );
      expect(
        cashHistory(
          snapshot,
          entries,
          AppCurrency.usd,
          DateSpan.month(DateTime(2027)),
          day,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'create a savings goal and transfer cash through the redesigned shell',
    (tester) async {
      final fixture = Phase4Fixture();
      await tester.runAsync(() async {
        await fixture.open(factory: databaseFactoryFfiNoIsolate);
        final repo = WalletRepository(fixture.database);
        await repo.save(
          const Wallet(
            id: 1,
            name: 'Main',
            type: WalletType.bank,
            currency: AppCurrency.usd,
            openingMinor: 10000,
          ),
        );
        await repo.save(
          const Wallet(
            name: 'Pocket',
            type: WalletType.cash,
            currency: AppCurrency.usd,
          ),
        );
      });
      final wallets = WalletRepository(fixture.database);
      final planning = PlanningRepository(fixture.database);
      final c = ProviderContainer(
        overrides: [
          appRuntimeProvider.overrideWithValue(fixture.runtime),
          transactionRepositoryProvider.overrideWithValue(
            SqfliteTransactionRepository(fixture.database),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepository(fixture.prefs),
          ),
          walletRepositoryProvider.overrideWithValue(wallets),
          planningRepositoryProvider.overrideWithValue(planning),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.runAsync(fixture.close);
      });
      await tester.runAsync(() async {
        await c.read(transactionsProvider.future);
        await c.read(walletsProvider.future);
        await c.read(planningProvider.future);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: AppTheme.light(), home: const AppShell()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'saving');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feature-savings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New goal'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Goal name'),
        'Rent buffer',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '300');
      final save = find.text('Save goal');
      await tester.ensureVisible(save);
      await tester.tap(save);
      for (
        var i = 0;
        i < 80 && find.text('New savings goal').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        });
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final g = (await planning.fetch()).goals.single;
        expect(
          (g.name, g.targetMinor, g.allocatedMinor),
          ('Rent buffer', 30000, 0),
        );
      });
      expect(find.text('New savings goal'), findsNothing);
      expect(find.text('Rent buffer'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Transfer money'));
      await tester.pumpAndSettle();
      for (final entry in [(0, 'Main (USD)'), (1, 'Pocket (USD)')]) {
        await tester.tap(
          find.byType(DropdownButtonFormField<int>).at(entry.$1),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$2).last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, '12.34');
      await tester.pumpAndSettle();
      expect(find.textContaining('Destination receives'), findsOneWidget);
      final confirm = find.text('Confirm transfer');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final after = await wallets.fetch();
        expect(after.transfers.single.sourceMinor, 1234);
        expect(after.balances, {1: 8766, 2: 1234});
      });
      await tester.pumpAndSettle();
      for (var i = 0; i < 80 && confirm.evaluate().isNotEmpty; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        });
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(confirm, findsNothing);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await openFeature(tester, MoneyFeature.calendar);
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-amount')),
        '32.25',
      );
      await tester.enterText(find.byKey(const ValueKey('entry-note')), 'Rent');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final details = find.text('More details');
      if (details.evaluate().isEmpty) {
        await tester.scrollUntilVisible(details, 240, scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        ).first);
      }
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      await tester.tap(details);
      await tester.pumpAndSettle();
      final schedule = find.text('Create a recurring schedule');
      await tester.ensureVisible(schedule);
      await tester.pumpAndSettle();
      await tester.tap(schedule.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('32.25'), findsOneWidget);
      final saveRule = find.text('Save recurring rule');
      await tester.scrollUntilVisible(
        saveRule,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(saveRule);
      for (
        var i = 0;
        i < 80 && find.text('New recurring rule').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        });
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add transaction'), findsOneWidget);
      await tester.runAsync(() async {
        final saved = await planning.fetch();
        expect(
          (
            saved.rules.single.name,
            saved.rules.single.amountMinor,
            saved.rules.single.automatic,
          ),
          ('Rent', 3225, false),
        );
        expect(
          await SqfliteTransactionRepository(fixture.database).fetchAll(),
          isEmpty,
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
