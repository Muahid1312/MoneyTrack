import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/data/repositories/managed_fund_repository.dart';
import 'package:moneytrack/features/managed_funds/application/managed_fund_providers.dart';
import 'package:moneytrack/features/managed_funds/presentation/managed_funds_screen.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/phase4_fixture.dart';

void main() {
  testWidgets(
    'create a fund, enter an itemized mixed purchase and reimburse it on a narrow screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = Phase4Fixture();
      await tester.runAsync(
        () => fixture.open(factory: databaseFactoryFfiNoIsolate),
      );
      final repo = ManagedFundRepository(fixture.database);
      final container = ProviderContainer(
        overrides: [
          managedFundRepositoryProvider.overrideWithValue(repo),
          currencyProvider.overrideWithValue(AppCurrency.afn),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await fixture.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.25)),
              child: child!,
            ),
            home: const ManagedFundsScreen(),
          ),
        ),
      );

      Future<void> waitFor(String text) async {
        final finder = find.text(text);
        for (
          var attempt = 0;
          attempt < 80 && finder.evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> tap(String text, {bool record = false}) async {
        final finder = record
            ? find.widgetWithText(ListTile, text)
            : find.text(text);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            210,
            scrollable: find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
          );
        }
        await tester.ensureVisible(finder.first);
        await tester.pump();
        await tester.tap(finder.hitTestable().first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> enter(String label, String value) async {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      await waitFor('No managed funds yet');
      await tap('New fund');
      await enter('Fund name', 'Home groceries');
      await enter('Provider', 'Father');
      await enter('Initial received amount (AFN)', '۵۰۰');
      await tap('Create fund');
      await waitFor('Available entrusted cash');
      await tap('Add purchase');
      await enter('Product or expense name', 'Flour');
      await tap('Use quantity and unit price');
      await enter('Quantity', '10');
      await enter('Unit (for example, kg)', 'kg');
      await enter('Unit price (AFN)', '80');
      await waitFor('Item total: 800.00 ؋');
      await tap('Entrusted cash');
      await tap('Both sources');
      await enter('Amount from entrusted cash (AFN)', '500');
      await tap('Save purchase');
      for (
        var i = 0;
        i < 80 && find.text('Save purchase').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Save purchase'), findsNothing);
      await waitFor('800.00 ؋');
      await tap('Flour', record: true);
      await tap('Reimburse advance');
      await enter('Amount (AFN)', '300');
      await tap('Save record');
      for (
        var i = 0;
        i < 80 && find.text('Save record').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Save record'), findsNothing);
      await waitFor('0.00 ؋');
      expect(find.text('Reimburse advance'), findsNothing);

      await tester.runAsync(() async {
        final snapshot = await repo.get(1);
        expect(
          (
            snapshot.ledger.cash,
            snapshot.ledger.expenses,
            snapshot.ledger.outstanding,
          ),
          (0, 80000, 0),
        );
        expect(snapshot.ledger.events, hasLength(3));
      });
      expect(tester.takeException(), isNull);
    },
  );
}
