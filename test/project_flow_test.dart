import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/project.dart';
import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/features/projects/application/project_providers.dart';
import 'package:moneytrack/features/projects/presentation/project_editor_screen.dart';
import 'package:moneytrack/features/projects/presentation/projects_screen.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('projects can be searched and business dashboard labels cash accounting', (tester) async {
    late Directory dir;
    late AppDatabase db;
    late ProjectRepository repo;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('project-ui-');
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
      repo = ProjectRepository(db);
      final now = DateTime(2026, 11, 8);
      for (final type in ProjectType.values) {
        await repo.save(Project(name: type == ProjectType.personal ? 'Family house' : 'Client studio',
          type: type, clientName: type == ProjectType.business ? 'Acme' : '', currency: AppCurrency.usd,
          budgetMinor: 10000, contractMinor: type == ProjectType.business ? 20000 : null,
          startDate: now, createdAt: now, updatedAt: now));
      }
    });
    final container = ProviderContainer(overrides: [
      projectRepositoryProvider.overrideWithValue(repo),
      transactionRepositoryProvider.overrideWithValue(SqfliteTransactionRepository(db)),
    ]);
    await tester.runAsync(() async {
      await container.read(transactionsProvider.future); await container.read(projectsProvider.future);
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: ProjectsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Family house'), findsOneWidget);
    expect(find.text('Client studio'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'acme');
    await tester.pumpAndSettle();
    expect(find.text('Family house'), findsNothing);
    expect(find.text('Client studio'), findsOneWidget);
    await tester.tap(find.text('Client studio'));
    await tester.pumpAndSettle();
    expect(find.text('Cash-based financial summary'), findsOneWidget);
    expect(find.text('Cash surplus is receipts minus payments, not accounting profit.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Outstanding client payments'), 200);
    expect(find.text('Outstanding client payments'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
    await tester.runAsync(() async { await db.close(); await dir.delete(recursive: true); });
  });

  testWidgets('new project validates name and distinguishes optional budget', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ProjectEditorScreen())));
    expect(find.text('Project name'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Save project'), 400,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    await tester.tap(find.text('Save project')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enter a project name'), -400,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    expect(find.text('Enter a project name'), findsOneWidget);
  });
}
