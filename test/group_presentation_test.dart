import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/repositories/group_repository.dart';
import 'package:moneytrack/features/groups/application/group_providers.dart';
import 'package:moneytrack/features/groups/presentation/groups_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/screen_capture.dart';
import 'support/visual_ledger.dart';

void main() {
  testWidgets(
    'Paghman list and four sections show actual contributions, expenses and refund shares',
    (tester) async {
      late Directory dir;
      late AppDatabase db;
      late GroupRepository repo;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('group-views-');
        sqfliteFfiInit();
        db = await AppDatabase.open(
          factory: databaseFactoryFfiNoIsolate,
          path: '${dir.path}/db',
          legacyCurrency: AppCurrency.afn,
        );
        await seedVisualLedger(db, DateTime(2026, 5, 23));
        repo = GroupRepository(db);
      });
      final container = ProviderContainer(
        overrides: [groupRepositoryProvider.overrideWithValue(repo)],
      );
      final key = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 780);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await db.close();
        await dir.delete(recursive: true);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });
      await loadCaptureFonts(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: const GroupsScreen(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 60 && find.text('650.00 ؋').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('3,000.00 ؋'), findsOneWidget);
      expect(find.text('650.00 ؋'), findsOneWidget);
      await captureView(tester, key, 'groups');
      await tester.tap(find.text('Paghman trip'));
      await tester.pumpAndSettle();
      await captureView(tester, key, 'group-overview');
      for (final route in [
        ('Members', 'group-members'),
        ('Expenses', 'group-expenses'),
        ('Settlement', 'group-settlement'),
      ]) {
        await tester.ensureVisible(find.text(route.$1).first);
        await tester.tap(find.text(route.$1).first);
        await tester.pumpAndSettle();
        await captureView(tester, key, route.$2);
        if (route.$1 == 'Members') {
          expect(find.textContaining('Expected 300.00'), findsWidgets);
        }
        if (route.$1 == 'Expenses') {
          expect(find.textContaining('Minibus rental'), findsWidgets);
        }
        if (route.$1 == 'Settlement') {
          expect(find.text('65.00 ؋'), findsWidgets);
        }
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Group cash · AFN'), findsOneWidget);
      await captureView(tester, key, 'group-large-dark');
      expect(tester.takeException(), isNull);
    },
  );
}
