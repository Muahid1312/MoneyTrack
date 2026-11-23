import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/features/explore/explore_screen.dart';
import 'package:moneytrack/features/groups/application/group_providers.dart';
import 'package:moneytrack/features/groups/domain/group_fund.dart';
import 'package:moneytrack/features/groups/presentation/groups_screen.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'support/phase4_fixture.dart';

void main() {
  test(
    'group registry supports activity aliases and opening a pinned tool',
    () {
      final f = MoneyFeature.groups;
      for (final query in [
        'trip fund',
        'shared expenses',
        'picnic',
        'football',
        'friends',
        'refund',
      ]) {
        expect(f.matches(query), isTrue, reason: query);
      }
      expect(f.available, isTrue);
    },
  );
  testWidgets(
    'create a trip, collect cash, calculate an item, confirm a plan and record a partial refund',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(415, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final f = Phase4Fixture();
      await tester.runAsync(() => f.open(factory: databaseFactoryFfiNoIsolate));
      final repo = GroupRepository(f.database);
      final container = ProviderContainer(
        overrides: [
          groupRepositoryProvider.overrideWithValue(repo),
          currencyProvider.overrideWithValue(AppCurrency.afn),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await f.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const GroupsScreen(),
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 90; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) break;
        }
        expect(finder, findsWidgets);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> tap(String s) async {
        final t = find.text(s).hitTestable();
        if (t.evaluate().isEmpty) {
          await tester.ensureVisible(find.text(s).first);
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.tap(find.text(s).hitTestable().first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> fill(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await waitFor(field);
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      await waitFor(find.textContaining('Create a group to collect'));
      await tap('New group');
      await fill('Group name', 'Football');
      await fill('Members', 'Ahmad\nOmid');
      await fill('Expected per member', '300');
      await tap('Create group');
      await waitFor(find.text('Settle project'));
      await tap('Add contribution');
      await fill('Amount', '300');
      await tap('Save');
      await waitFor(find.text('Settle project'));
      await tap('Add expense');
      await fill('Item', 'Bottled water');
      await tap('Quantity and receipt');
      await tester.pumpAndSettle();
      await fill('Quantity', '10');
      await fill('Unit price', '25');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('Amount')))
            .controller!
            .text,
        '250.00',
      );
      await tap('Save');
      await waitFor(find.text('Settle project'));
      await tap('Settle project');
      await tester.pumpAndSettle();
      await tap('Review and confirm plan');
      await waitFor(find.text('Confirm settlement plan'));
      await tap('Confirm');
      await waitFor(find.textContaining('Pay 50.00'));
      await tap('Pay 50.00 ؋');
      await fill('Amount', '20');
      await tap('Save');
      await waitFor(find.textContaining('Partially paid'));
      await tester.runAsync(() async {
        final g = await repo.get(1);
        expect(g.stage, TripStage.settlement);
        expect(
          [g.collected, g.cash, g.spent, g.refunded, g.dueRefund(1)],
          [30000, 3000, 25000, 2000, 3000],
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
