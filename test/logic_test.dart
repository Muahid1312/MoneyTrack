import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/utils/amount_input.dart';
import 'package:moneytrack/core/utils/csv_exporter.dart';
import 'package:moneytrack/core/utils/date_utils.dart';
import 'package:moneytrack/core/utils/money.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/features/budgets/domain/budget_calculator.dart';
import 'package:moneytrack/features/statistics/domain/finance_calculator.dart';
import 'package:moneytrack/features/transactions/application/transaction_filter.dart';

TransactionModel tx(int id, TransactionType type, int minor, String cat, DateTime at,
        {String note = ''}) =>
    TransactionModel(
      id: id,
      type: type,
      amountMinor: minor,
      categoryId: cat,
      note: note,
      occurredAt: at,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  group('Money', () {
    test('formats minor units exactly', () {
      expect(Money.format(123456, AppCurrency.usd), r'$1,234.56');
      expect(Money.format(5, AppCurrency.eur), '€0.05');
      expect(Money.format(-1000, AppCurrency.usd), r'−$10.00');
      expect(Money.format(1000, AppCurrency.usd, signed: true), r'+$10.00');
      expect(Money.format(250000, AppCurrency.afn), '2,500.00 ؋');
    });

    test('0.1 + 0.2 stays exact in minor units', () {
      final a = Money.parseMinor('0.1')!;
      final b = Money.parseMinor('0.2')!;
      expect(a + b, 30);
      expect(Money.format(a + b, AppCurrency.usd), r'$0.30');
    });

    test('parseMinor validates', () {
      expect(Money.parseMinor('12'), 1200);
      expect(Money.parseMinor('12.5'), 1250);
      expect(Money.parseMinor('12.05'), 1205);
      expect(Money.parseMinor('12.555'), isNull);
      expect(Money.parseMinor('-3'), isNull);
      expect(Money.parseMinor('abc'), isNull);
      expect(Money.parseMinor(''), isNull);
    });

    test('compact', () {
      expect(Money.compact(123400, AppCurrency.usd), r'$1.2K');
      expect(Money.compact(250000000, AppCurrency.usd), r'$2.5M');
      expect(Money.compact(9900, AppCurrency.usd), r'$99');
    });

    test('plain', () {
      expect(Money.plain(-1205), '-12.05');
      expect(Money.plain(7), '0.07');
    });
  });

  group('AmountInput', () {
    test('typing and limits', () {
      var a = const AmountInput();
      a = a.appendDigit(0).appendDigit(0);
      expect(a.raw, '0');
      a = a.appendDigit(5).appendDecimal().appendDigit(2).appendDigit(5).appendDigit(9);
      expect(a.raw, '5.25');
      expect(a.minor, 525);
      a = a.appendDecimal();
      expect(a.raw, '5.25');
      a = a.backspace().backspace().backspace();
      expect(a.raw, '5');
    });

    test('grouped display and round trip', () {
      var a = const AmountInput();
      for (final d in [1, 2, 3, 4, 5, 6, 7]) {
        a = a.appendDigit(d);
      }
      expect(a.display, '1,234,567');
      expect(AmountInput.fromMinor(123450).raw, '1234.5');
      expect(AmountInput.fromMinor(123405).raw, '1234.05');
      expect(AmountInput.fromMinor(100).raw, '1');
    });

    test('max integer digits', () {
      var a = const AmountInput();
      for (var i = 0; i < 12; i++) {
        a = a.appendDigit(9);
      }
      expect(a.raw.length, AmountInput.maxIntegerDigits);
    });

    test('leading decimal', () {
      expect(const AmountInput().appendDecimal().appendDigit(5).minor, 50);
    });
  });

  group('FinanceCalculator', () {
    final now = DateTime(2026, 10, 21, 15);
    final data = [
      tx(1, TransactionType.income, 300000, 'salary', DateTime(2026, 10, 1, 9)),
      tx(2, TransactionType.expense, 4550, 'food', DateTime(2026, 10, 20, 12)),
      tx(3, TransactionType.expense, 12000, 'transport', DateTime(2026, 10, 21, 8)),
      tx(4, TransactionType.expense, 999, 'food', DateTime(2026, 10, 15, 19)),
      tx(5, TransactionType.expense, 50000, 'housing', DateTime(2026, 9, 5)),
      tx(6, TransactionType.income, 10000, 'freelance', DateTime(2026, 9, 20)),
    ];

    test('totals and balance', () {
      final oct = FinanceCalculator.totals(data, span: DateSpan.month(now));
      expect(oct.income, 300000);
      expect(oct.expense, 4550 + 12000 + 999);
      expect(oct.count, 4);
      expect(FinanceCalculator.balance(data), 310000 - (4550 + 12000 + 999 + 50000));
    });

    test('daily expenses for the last week', () {
      final first = Dates.addDays(Dates.dateOnly(now), -6);
      final days = FinanceCalculator.dailyExpenses(data, first, 7);
      expect(days.length, 7);
      expect(days[6], 12000);
      expect(days[5], 4550);
      expect(days[0], 999);
    });

    test('category breakdown sorted with fractions summing to 1', () {
      final shares = FinanceCalculator.expenseByCategory(data, DateSpan.month(now));
      expect(shares.first.category.id, 'transport');
      expect(shares.map((s) => s.amountMinor).reduce((a, b) => a + b), 17549);
      expect(shares.fold<double>(0, (s, c) => s + c.fraction), closeTo(1, 1e-9));
      expect(shares.firstWhere((s) => s.category.id == 'food').count, 2);
    });

    test('monthly buckets', () {
      final span = DateSpan(DateTime(2026, 9), DateTime(2026, 11));
      final b = FinanceCalculator.buckets(data, span, BucketSize.month);
      expect(b.length, 2);
      expect(b[0].expense, 50000);
      expect(b[0].income, 10000);
      expect(b[1].income, 300000);
    });

    test('weekly and daily buckets cover the span', () {
      final span = DateSpan.month(now);
      final weeks = FinanceCalculator.buckets(data, span, BucketSize.week);
      expect(weeks.length, 5);
      expect(weeks.fold<int>(0, (s, w) => s + w.expense), 17549);
      final days = FinanceCalculator.buckets(data, span, BucketSize.day);
      expect(days.length, 31);
      expect(days[20].expense, 12000);
    });

    test('average daily expense ignores future days', () {
      final avg = FinanceCalculator.averageDailyExpense(data, DateSpan.month(now), now);
      expect(avg, (17549 / 21).round());
    });

    test('percent change', () {
      expect(FinanceCalculator.percentChange(0, 10), isNull);
      expect(FinanceCalculator.percentChange(100, 150), 50);
    });
  });

  group('BudgetCalculator', () {
    final now = DateTime(2026, 10, 21);
    List<TransactionModel> spend(int minor) =>
        [tx(1, TransactionType.expense, minor, 'food', DateTime(2026, 10, 2))];

    test('levels', () {
      expect(BudgetCalculator.compute(budgetMinor: 0, transactions: spend(10), now: now).level,
          BudgetLevel.notSet);
      expect(
          BudgetCalculator.compute(budgetMinor: 100000, transactions: spend(50000), now: now).level,
          BudgetLevel.healthy);
      expect(
          BudgetCalculator.compute(budgetMinor: 100000, transactions: spend(80000), now: now).level,
          BudgetLevel.approaching);
      expect(
          BudgetCalculator.compute(budgetMinor: 100000, transactions: spend(100000), now: now).level,
          BudgetLevel.approaching);
      expect(
          BudgetCalculator.compute(budgetMinor: 100000, transactions: spend(100001), now: now).level,
          BudgetLevel.exceeded);
    });

    test('remaining, allowance, projection', () {
      final s = BudgetCalculator.compute(budgetMinor: 100000, transactions: spend(42000), now: now);
      expect(s.remainingMinor, 58000);
      expect(s.daysLeft, 11); // Oct 21..31
      expect(s.dailyAllowanceMinor, 58000 ~/ 11);
      expect(s.projectedMinor, (42000 / 21 * 31).round());
    });

    test('ignores income and other months', () {
      final s = BudgetCalculator.compute(budgetMinor: 1000, transactions: [
        tx(1, TransactionType.income, 999999, 'salary', DateTime(2026, 10, 3)),
        tx(2, TransactionType.expense, 500, 'food', DateTime(2026, 9, 30)),
      ], now: now);
      expect(s.spentMinor, 0);
    });
  });

  group('Filter & CSV', () {
    final now = DateTime(2026, 10, 21);
    final a = tx(1, TransactionType.expense, 1500, 'food', DateTime(2026, 10, 20), note: 'Lunch, "team"');
    final b = tx(2, TransactionType.income, 9000, 'salary', DateTime(2026, 9, 1));

    test('filter combines query, type, category and date', () {
      const f = TransactionFilter(query: 'lunch');
      expect(f.matches(a, null), isTrue);
      expect(f.matches(b, null), isFalse);
      const byCat = TransactionFilter(query: 'food');
      expect(byCat.matches(a, null), isTrue);
      const typeF = TransactionFilter(type: TransactionType.income);
      expect(typeF.matches(b, null), isTrue);
      const month = TransactionFilter(date: DateFilter.thisMonth);
      expect(month.matches(b, month.resolveSpan(now)), isFalse);
      expect(month.matches(a, month.resolveSpan(now)), isTrue);
    });

    test('csv escapes and keeps exact decimals', () {
      final csv = CsvExporter.build([a, b], 'USD');
      final lines = csv.trim().split('\r\n');
      expect(lines.first, startsWith('id,date,time,type'));
      expect(lines[1], contains('"Lunch, ""team"""'));
      expect(lines[1], contains(',15.00,-15.00,USD'));
      expect(lines[2], contains(',90.00,90.00,USD'));
    });
  });
}
