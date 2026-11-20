import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneytrack/data/models/planning.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/features/budgets/presentation/wallet_budget_panel.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'support/fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/budgets/domain/wallet_budget.dart';
import 'support/phase4_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TransactionModel expense(
    DateTime when,
    int amount, {
    int wallet = 1,
    AppCurrency currency = AppCurrency.afn,
    String category = 'food',
    bool income = false,
  }) => TransactionModel(
    type: income ? TransactionType.income : TransactionType.expense,
    walletId: wallet,
    currency: currency,
    categoryId: category,
    amountMinor: amount,
    occurredAt: when,
    createdAt: when,
    updatedAt: when,
  );

  testWidgets(
    'dashboard keeps spendable wallet cash and category allowance separate',
    (tester) async {
      final monday = DateTime(2026, 1, 5);
      const wallet = Wallet(
        id: 1,
        name: 'Cash',
        type: WalletType.cash,
        currency: AppCurrency.afn,
      );
      final budget = WalletBudget(
        walletId: 1,
        period: BudgetPeriod.weekly,
        category: 'food',
        limit: 100000,
        start: monday,
      );
      SharedPreferences.setMockInitialValues({'currency': 'AFN'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => monday),
            settingsRepositoryProvider.overrideWithValue(
              SettingsRepository(prefs),
            ),
            transactionRepositoryProvider.overrideWithValue(
              InMemoryTransactionRepository([expense(monday, 20000)]),
            ),
            walletsProvider.overrideWith(
              (_) async => const WalletSnapshot(
                [wallet],
                {1: 2000000},
                [],
                reserved: {1: 500000},
              ),
            ),
            planningProvider.overrideWith(
              (_) async => PlanningSnapshot(
                budgets: [budget],
                debts: [],
                postings: [],
                goals: [],
                savingsEvents: [],
                rules: [],
                occurrences: [],
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: WalletBudgetPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Wallet cash   20,000.00 ؋'), findsOneWidget);
      expect(
        find.textContaining('Reserved savings   5,000.00 ؋'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Available cash   15,000.00 ؋'),
        findsOneWidget,
      );
      expect(find.textContaining('Remaining 800.00 ؋'), findsOneWidget);
    },
  );
  test(
    'calendar boundaries include Monday, leap day and the full custom end date',
    () {
      final leap = DateTime(2024, 2, 29, 23, 59);
      expect(periodStart(BudgetPeriod.daily, leap), DateTime(2024, 2, 29));
      expect(
        periodStart(BudgetPeriod.weekly, DateTime(2023, 1, 1)),
        DateTime(2022, 12, 26),
      );
      expect(periodStart(BudgetPeriod.monthly, leap), DateTime(2024, 2));
      final budget = WalletBudget(
        walletId: 1,
        limit: 100,
        period: BudgetPeriod.custom,
        start: DateTime(2024, 2, 28),
        end: DateTime(2024, 2, 29),
      );
      final rows = [
        expense(DateTime(2024, 2, 27, 23, 59), 90),
        expense(leap, 25),
      ];
      expect(budget.status(leap, AppCurrency.afn, rows)?.remaining, 75);
      expect(budget.status(DateTime(2024, 3), AppCurrency.afn, rows), isNull);
      for (final period in [
        BudgetPeriod.daily,
        BudgetPeriod.weekly,
        BudgetPeriod.monthly,
      ]) {
        final start = periodStart(period, leap);
        final next = switch (period) {
          BudgetPeriod.daily => DateTime(2024, 3),
          BudgetPeriod.weekly => DateTime(2024, 3, 4),
          _ => DateTime(2024, 3),
        };
        final plan = WalletBudget(
          walletId: 1,
          limit: 100,
          period: period,
          start: start,
        );
        expect(
          plan.status(next, AppCurrency.afn, [
            expense(leap, 75),
            expense(next, 10),
          ])?.spent,
          10,
        );
      }
    },
  );

  test(
    'positive rollover accumulates through empty weeks and restarts after overspending',
    () {
      final start = DateTime(2026, 1, 5);
      final budget = WalletBudget(
        walletId: 1,
        limit: 100,
        period: BudgetPeriod.weekly,
        start: start,
        category: 'food',
        rollover: true,
      );
      final rows = [
        expense(start, 40),
        expense(start, 90, wallet: 2),
        expense(start, 800, currency: AppCurrency.usd),
        expense(start, 80, category: 'other'),
        expense(start, 70, income: true),
        expense(DateTime(2026, 1, 19), 300),
      ];
      expect(budget.status(DateTime(2026, 1, 19), AppCurrency.afn, rows), (
        spent: 300,
        carry: 160,
        remaining: -40,
      ));
      expect(budget.status(DateTime(2026, 1, 26), AppCurrency.afn, rows), (
        spent: 0,
        carry: 0,
        remaining: 100,
      ));
    },
  );

  test(
    'budget never reserves cash and confirmed emergency withdrawals use the ledger',
    () async {
      final f = Phase4Fixture();
      await f.open();
      try {
        final db = f.database;
        final repo = PlanningRepository(db), wallets = WalletRepository(db);
        await db.db.update('wallets', {
          'opening_minor': 2000000,
        }, where: 'id=1');
        await repo.saveBudget(
          WalletBudget(
            walletId: 1,
            period: BudgetPeriod.daily,
            limit: 80000,
            start: DateTime(2026, 1, 5),
          ),
        );
        expect((await wallets.fetch()).available(1), 2000000);
        final goal = await repo.saveGoal(
          goalName: 'Emergency',
          walletId: 1,
          targetMinor: 700000,
          emergency: true,
          weeklyMinor: 5000,
        );
        await repo.goalEvent(goal, 500000, 'contribution');
        final funded = await wallets.fetch();
        expect(funded.available(1), 1500000);
        expect(funded.balances[1], 2000000);
        await expectLater(
          repo.goalEvent(goal, -10000, 'stale', expectedReserved: 400000),
          throwsStateError,
        );
        await repo.goalEvent(
          goal,
          -10000,
          'withdraw',
          expectedReserved: 500000,
        );
        expect((await wallets.fetch()).available(1), 1510000);
        final data = await repo.fetch();
        expect(data.savingsEvents.length, 2);
        expect(data.goals.single.allocatedMinor, 490000);
        expect(data.goals.single.emergency, isTrue);
        expect(data.goals.single.weeklyMinor, 5000);
        expect(await db.db.query('transactions'), isEmpty);
      } finally {
        await f.close();
      }
    },
  );
}
