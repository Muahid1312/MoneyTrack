import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moneytrack/app/app.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/groups/application/group_providers.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/visual_ledger.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture populated MoneyTrack views on Android', (tester) async {
    final temp = await (await getTemporaryDirectory()).createTemp(
      'moneytrack-visual-',
    );
    final db = await AppDatabase.open(
      path: '${temp.path}/review.db',
      legacyCurrency: AppCurrency.afn,
    );
    SharedPreferences.setMockInitialValues({
      'currency': 'AFN',
      'monthly_budget_minor': 220000,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        transactionRepositoryProvider.overrideWithValue(
          SqfliteTransactionRepository(db),
        ),
        walletRepositoryProvider.overrideWithValue(WalletRepository(db)),
        groupRepositoryProvider.overrideWithValue(GroupRepository(db)),
        planningRepositoryProvider.overrideWithValue(PlanningRepository(db)),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await db.close();
      await temp.delete(recursive: true);
    });
    await seedVisualLedger(db, DateTime.now());
    await c.read(walletsProvider.future);
    await c.read(transactionsProvider.future);
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(key: key, child: const MoneyTrackApp()),
      ),
    );
    final pictures = <String, String>{};
    Future<void> picture(String name, Finder marker) async {
      await tester.pumpAndSettle();
      for (var i = 0; i < 60 && marker.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(marker, findsWidgets, reason: name);
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      try {
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        pictures[name] = base64Encode(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        img.dispose();
      }
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f.first);
      await tester.tap(f.first);
      await tester.pumpAndSettle();
    }

    Future<void> tab(String name) =>
        tap(find.widgetWithText(NavigationDestination, name));
    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await picture('calendar', find.textContaining('Lunch with friends'));
    await tap(find.text('Daily'));
    await picture('daily', find.textContaining('Lunch with friends'));
    await tap(find.byTooltip('Add transaction'));
    await picture('entry', find.text('New transaction'));
    await back();
    await tab('Statistics');
    await picture('statistics', find.text('Food & Dining'));
    await tab('Accounts');
    await picture('accounts', find.text('Travel account'));
    await tap(find.byTooltip('Transfer money'));
    await picture('transfer', find.text('Transfer money'));
    await back();
    await tab('More');
    await picture('more', find.text('Group Money'));
    await tap(find.byKey(const ValueKey('feature-groups')));
    await picture('groups', find.text('650.00 ؋'));
    await tap(find.text('Paghman trip'));
    await picture('group-overview', find.text('Add contribution'));
    for (final item in [
      ('Members', 'group-members', 'Ahmad'),
      ('Expenses', 'group-expenses', 'Snacks'),
      ('Settlement', 'group-settlement', 'Refund preview'),
    ]) {
      await tap(find.widgetWithText(Tab, item.$1));
      await picture(item.$2, find.text(item.$3));
    }
    await back();
    await back();
    await tester.enterText(find.byType(TextField), 'monthly limit');
    await tester.pumpAndSettle();
    await tap(find.byKey(const ValueKey('feature-monthly')));
    await picture('budget', find.text('Remaining'));
    await back();
    await tester.enterText(find.byType(TextField), 'appearance');
    await tester.pumpAndSettle();
    await tap(find.byKey(const ValueKey('feature-appearance')));
    await tap(find.text('Dark'));
    await picture('appearance-dark', find.text('Use device setting'));
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
    await back();
    await tab('Transactions');
    await tap(find.text('Calendar'));
    await picture('calendar-dark', find.text('Calendar'));
    expect(tester.takeException(), isNull);
    binding.reportData = {'screens': pictures};
  });
}
