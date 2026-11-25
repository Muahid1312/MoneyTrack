import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:moneytrack/features/wallets/presentation/wallets_screen.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'support/fakes.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('overview shows separate currency balances and create-wallet form', (tester) async {
    late AppDatabase database;
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('moneytrack-wallet-ui-');
      database = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
      final repo = WalletRepository(database);
      await repo.save(const Wallet(name: 'Afghan savings', type: WalletType.savings,
        currency: AppCurrency.afn, openingMinor: 700000));
    });
    final repo = WalletRepository(database);
    final container = ProviderContainer(overrides: [
      walletRepositoryProvider.overrideWithValue(repo),
      transactionRepositoryProvider.overrideWithValue(InMemoryTransactionRepository()),
    ]);
    await tester.runAsync(() async { await container.read(transactionsProvider.future); await container.read(walletsProvider.future); });
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: WalletsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Available'), findsWidgets);
    expect(find.text('Afghan Afghani · AFN'), findsOneWidget);
    expect(find.text('US Dollar · USD'), findsOneWidget);
    expect(find.text('Afghan savings'), findsOneWidget);
    expect(find.text('7,000.00 ؋'), findsWidgets);
    await tester.tap(find.text('Afghan savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reconcile balance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6950');
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Difference: −50.00 ؋'), findsOneWidget);
    await tester.tap(find.text('Review wallet history'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final snapshot = await repo.fetch();
      expect(snapshot.balances[2], 700000);
      expect(snapshot.transfers, isEmpty);
    });
    await tester.tap(find.text('New wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet name'), findsOneWidget);
    expect(find.text('Wallet type'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    await tester.tap(find.text('Save wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(() async { await database.close(); await dir.delete(recursive: true); });
  });

  testWidgets('transfer needs two active wallets and never assumes a foreign rate', (tester) async {
    late AppDatabase database;
    late Directory dir;
    late WalletRepository repo;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('moneytrack-transfer-ui-');
      database = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
      repo = WalletRepository(database);
    });
    final container = ProviderContainer(overrides: [
      walletRepositoryProvider.overrideWithValue(repo),
      transactionRepositoryProvider.overrideWithValue(InMemoryTransactionRepository()),
    ]);
    await tester.runAsync(() async { await container.read(transactionsProvider.future); await container.read(walletsProvider.future); });
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: TransferScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Create at least two active wallets to transfer money.'), findsOneWidget);
    await tester.runAsync(() async {
      await repo.save(const Wallet(name: 'AFN', type: WalletType.cash, currency: AppCurrency.afn));
      container.invalidate(walletsProvider);
      await container.read(transactionsProvider.future); await container.read(walletsProvider.future);
    });
    await tester.pumpAndSettle();
    expect(find.text('Manual exchange rate'), findsOneWidget);
    expect(find.textContaining('No rate is fetched or assumed.'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm transfer'));
    await tester.tap(find.text('Confirm transfer'));
    await tester.pumpAndSettle();
    expect(find.text('Choose two different wallets'), findsOneWidget);
    await tester.runAsync(() async { expect((await repo.fetch()).transfers, isEmpty); });
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(() async { await database.close(); await dir.delete(recursive: true); });
  });
}
