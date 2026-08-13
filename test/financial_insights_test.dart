import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/models/financial_insights.dart';
import 'package:smartexpense/core/models/recurring_expense_model.dart';
import 'package:smartexpense/services/financial_insights_service.dart';

/// Fixed "now" so month boundaries are deterministic.
final now = DateTime(2026, 8, 15, 12);
final thisMonth = DateTime(2026, 8, 5);
final lastMonth = DateTime(2026, 7, 5);

ExpenseModel tx({
  required double amount,
  required bool isExpense,
  DateTime? date,
  String category = 'Other',
  String title = 'Item',
  bool isWindfall = false,
}) {
  return ExpenseModel(
    id: '$title-$amount-${date ?? thisMonth}-$isWindfall',
    title: title,
    amount: amount,
    category: category,
    date: date ?? thisMonth,
    isExpense: isExpense,
    isWindfall: isWindfall,
  );
}

FinancialInsights build(
  List<ExpenseModel> transactions, {
  List<RecurringExpenseModel> recurring = const [],
}) {
  return FinancialInsightsService.compute(
    transactions: transactions,
    recurring: recurring,
    bills: const [],
    now: now,
  );
}

RecurringExpenseModel recurring({
  required double amount,
  required RecurringFrequency frequency,
  int interval = 1,
  RecurringStatus status = RecurringStatus.active,
}) {
  return RecurringExpenseModel(
    id: 'r-$amount-${frequency.name}',
    userId: 'u',
    title: 'Rent',
    category: 'Bills',
    amount: amount,
    currency: 'NPR',
    frequency: frequency,
    interval: interval,
    startDate: lastMonth,
    nextDueDate: now.add(const Duration(days: 3)),
    status: status,
    createdAt: lastMonth,
    updatedAt: lastMonth,
  );
}

void main() {
  group('totals', () {
    test('sum the entire history, not a recent slice', () {
      // The old prompt summed only the 18 most recent rows and presented the
      // result as a lifetime total, so anyone with more history was quoted
      // wrong numbers.
      final many = [
        for (var i = 0; i < 40; i++)
          tx(
            amount: 100,
            isExpense: true,
            date: DateTime(2026, 8, 1).add(Duration(hours: i)),
          ),
        tx(amount: 50000, isExpense: false, date: DateTime(2026, 1, 2)),
      ];

      final insights = build(many);

      expect(insights.transactionCount, 41);
      expect(insights.totalExpensePaisa, 40 * 10000);
      expect(insights.totalIncomePaisa, 5000000);
      expect(insights.balancePaisa, 5000000 - 400000);
    });

    test('balance is income minus expenditure', () {
      final insights = build([
        tx(amount: 1000, isExpense: false),
        tx(amount: 250, isExpense: true),
      ]);

      expect(insights.balancePaisa, 75000);
    });

    test('empty history reports no data', () {
      final insights = build(const []);

      expect(insights.hasData, isFalse);
      expect(insights.balancePaisa, 0);
      expect(insights.stance, CoachStance.calm);
    });
  });

  group('monthly difference', () {
    test('separates this month from last month', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 400, isExpense: true, date: thisMonth),
        tx(amount: 900, isExpense: false, date: lastMonth),
        tx(amount: 800, isExpense: true, date: lastMonth),
      ]);

      expect(insights.thisMonth.incomePaisa, 100000);
      expect(insights.thisMonth.expensePaisa, 40000);
      expect(insights.thisMonth.netPaisa, 60000);
      expect(insights.lastMonth.netPaisa, 10000);
    });

    test('savings rate is the share of income kept', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 250, isExpense: true, date: thisMonth),
      ]);

      expect(insights.thisMonth.savingsRate, closeTo(0.75, 0.0001));
    });

    test('savings rate is null without income to measure against', () {
      final insights = build([
        tx(amount: 250, isExpense: true, date: thisMonth),
      ]);

      expect(insights.thisMonth.savingsRate, isNull);
    });

    test('spending change compares the two months', () {
      final insights = build([
        tx(amount: 150, isExpense: true, date: thisMonth),
        tx(amount: 100, isExpense: true, date: lastMonth),
      ]);

      expect(insights.spendingChangeRatio, closeTo(0.5, 0.0001));
    });
  });

  group('category insights', () {
    test('rank by size and carry last month as a baseline', () {
      final insights = build([
        tx(amount: 600, isExpense: true, category: 'Food', date: thisMonth),
        tx(amount: 200, isExpense: true, category: 'Travel', date: thisMonth),
        tx(amount: 300, isExpense: true, category: 'Food', date: lastMonth),
      ]);

      final food = insights.topCategories.first;
      expect(food.label, 'Food');
      expect(food.paisa, 60000);
      expect(food.previousPaisa, 30000);
      expect(food.changeRatio, closeTo(1.0, 0.0001));
      expect(food.share, closeTo(0.75, 0.0001));
      expect(insights.topCategories[1].label, 'Travel');
    });

    test('flags a category with no prior baseline as new', () {
      final insights = build([
        tx(amount: 200, isExpense: true, category: 'Travel', date: thisMonth),
      ]);

      expect(insights.topCategories.single.isNew, isTrue);
      expect(insights.topCategories.single.changeRatio, isNull);
    });
  });

  group('pace and runway', () {
    test('daily burn averages the last 30 days', () {
      final insights = build([
        tx(
          amount: 300,
          isExpense: true,
          date: now.subtract(const Duration(days: 2)),
        ),
        // Outside the window, must not count.
        tx(
          amount: 9000,
          isExpense: true,
          date: now.subtract(const Duration(days: 90)),
        ),
      ]);

      expect(insights.last30DaysExpensePaisa, 30000);
      expect(insights.dailyBurnPaisa, 1000);
    });

    test('runway is null when the balance is already negative', () {
      final insights = build([
        tx(
          amount: 500,
          isExpense: true,
          date: now.subtract(const Duration(days: 1)),
        ),
      ]);

      expect(insights.balancePaisa, lessThan(0));
      expect(insights.runwayDays, isNull);
    });

    test('rounds the daily average to whole rupees for display', () {
      final insights = build([
        tx(
          amount: 57050,
          isExpense: true,
          date: now.subtract(const Duration(days: 1)),
        ),
      ]);

      // 57,050 / 30 = 1,901.666..., which should not be shown to that
      // precision.
      expect(insights.dailyBurnPaisa, 190167);
      expect(insights.dailyBurnRoundedPaisa, 190200);
      expect(insights.dailyBurnRoundedPaisa % 100, 0);
    });

    test('runway divides balance by burn', () {
      final insights = build([
        tx(amount: 30000, isExpense: false, date: DateTime(2026, 1, 1)),
        tx(
          amount: 300,
          isExpense: true,
          date: now.subtract(const Duration(days: 1)),
        ),
      ]);

      // Balance 29,700 at a burn of 10/day.
      expect(insights.dailyBurnPaisa, 1000);
      expect(insights.runwayDays, 2970);
    });
  });

  group('recurring commitments', () {
    test('normalise every frequency to a monthly figure', () {
      final insights = build(
        const [],
        recurring: [
          recurring(amount: 300, frequency: RecurringFrequency.monthly),
          recurring(amount: 1200, frequency: RecurringFrequency.yearly),
          recurring(amount: 100, frequency: RecurringFrequency.weekly),
        ],
      );

      // 300 + (1200/12 = 100) + (100 * 52/12 = 433.33)
      expect(insights.committedMonthlyPaisa, closeTo(83333, 100));
    });

    test('ignore paused commitments', () {
      final insights = build(
        const [],
        recurring: [
          recurring(
            amount: 500,
            frequency: RecurringFrequency.monthly,
            status: RecurringStatus.paused,
          ),
        ],
      );

      expect(insights.committedMonthlyPaisa, 0);
    });
  });

  group('coach stance', () {
    test('is strict when spending exceeds income this month', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 1500, isExpense: true, date: thisMonth),
      ]);

      expect(insights.stance, CoachStance.strict);
      expect(insights.concerns, isNotEmpty);
    });

    test('is strict when the overall balance has gone negative', () {
      // A good month does not earn a relaxed tone while the running balance is
      // still underwater.
      final insights = build([
        tx(amount: 100, isExpense: false, date: lastMonth),
        tx(amount: 9000, isExpense: true, date: lastMonth),
        tx(amount: 5000, isExpense: false, date: thisMonth),
        tx(amount: 100, isExpense: true, date: thisMonth),
      ]);

      expect(insights.thisMonth.savingsRate, greaterThan(0.9));
      expect(insights.balancePaisa, lessThan(0));
      expect(insights.stance, CoachStance.strict);
    });

    test('is encouraging on a healthy savings rate', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 200, isExpense: true, date: thisMonth),
      ]);

      expect(insights.stance, CoachStance.encouraging);
      expect(insights.wins, isNotEmpty);
    });

    test('is watchful when savings are thin', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 950, isExpense: true, date: thisMonth),
      ]);

      expect(insights.stance, CoachStance.watchful);
    });

    test('does not celebrate lower spending in a month with no entries', () {
      // Early in a month an empty ledger looks like a huge drop; congratulating
      // that is worse than saying nothing.
      final insights = build([
        tx(amount: 5000, isExpense: true, date: lastMonth),
        tx(amount: 20000, isExpense: false, date: lastMonth),
      ]);

      expect(insights.thisMonth.hasActivity, isFalse);
      expect(
        insights.wins.any((win) => win.contains('Spending is down')),
        isFalse,
      );
    });

    test('does celebrate lower spending once the month has entries', () {
      final insights = build([
        tx(amount: 5000, isExpense: true, date: lastMonth),
        tx(amount: 20000, isExpense: false, date: lastMonth),
        tx(amount: 1000, isExpense: true, date: thisMonth),
      ]);

      expect(
        insights.wins.any((win) => win.contains('Spending is down')),
        isTrue,
      );
    });

    test('is watchful when a large category spikes', () {
      final insights = build([
        tx(amount: 10000, isExpense: false, date: thisMonth),
        tx(amount: 2000, isExpense: true, category: 'Food', date: thisMonth),
        tx(amount: 500, isExpense: true, category: 'Food', date: lastMonth),
        tx(amount: 5000, isExpense: false, date: lastMonth),
      ]);

      expect(insights.stance, CoachStance.watchful);
      expect(
        insights.concerns.any((concern) => concern.contains('Food')),
        isTrue,
      );
    });

    test('strict outranks a spike so the firmest signal wins', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 3000, isExpense: true, category: 'Food', date: thisMonth),
        tx(amount: 100, isExpense: true, category: 'Food', date: lastMonth),
      ]);

      expect(insights.stance, CoachStance.strict);
    });

    test('every stance carries a distinct tone directive', () {
      final directives = CoachStance.values
          .map((stance) => stance.directive)
          .toSet();

      expect(directives.length, CoachStance.values.length);
      expect(CoachStance.strict.directive.toLowerCase(), contains('direct'));
    });
  });

  group('headline', () {
    test('names the overspend when the month is negative', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 1500, isExpense: true, date: thisMonth),
      ]);

      expect(insights.headline, contains('Over by'));
    });

    test('names what was kept when the month is positive', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 400, isExpense: true, date: thisMonth),
      ]);

      expect(insights.headline, contains('Kept'));
    });

    test('distinguishes an empty month from a balanced one', () {
      final quietMonth = build([
        tx(amount: 1000, isExpense: false, date: lastMonth),
      ]);
      expect(quietMonth.headline, 'No entries this month');

      final balanced = build([
        tx(amount: 500, isExpense: false, date: thisMonth),
        tx(amount: 500, isExpense: true, date: thisMonth),
      ]);
      expect(balanced.headline, 'Breaking even this month');
    });
  });

  group('one-off income', () {
    test('is excluded from the savings rate', () {
      // The real case: a Rs. 85 lakh land sale alongside a normal salary made
      // the rate read 99% and skewed every judgement built on it.
      final insights = build([
        tx(amount: 50000, isExpense: false, date: thisMonth, title: 'Salary'),
        tx(
          amount: 8500000,
          isExpense: false,
          date: thisMonth,
          title: 'Sale of land',
          isWindfall: true,
        ),
        tx(amount: 25000, isExpense: true, date: thisMonth),
      ]);

      // 50,000 regular income against 25,000 spent.
      expect(insights.thisMonth.savingsRate, closeTo(0.5, 0.0001));
      expect(insights.thisMonth.regularIncomePaisa, 5000000);
      expect(insights.thisMonth.hasWindfall, isTrue);
    });

    test('still counts towards income, balance and net', () {
      final insights = build([
        tx(
          amount: 1000,
          isExpense: false,
          date: thisMonth,
          isWindfall: true,
        ),
      ]);

      expect(insights.totalIncomePaisa, 100000);
      expect(insights.balancePaisa, 100000);
      expect(insights.thisMonth.netPaisa, 100000);
    });

    test('a month of only one-off income has no meaningful rate', () {
      final insights = build([
        tx(
          amount: 1000,
          isExpense: false,
          date: thisMonth,
          isWindfall: true,
        ),
        tx(amount: 200, isExpense: true, date: thisMonth),
      ]);

      expect(insights.thisMonth.savingsRate, isNull);
    });

    test('ordinary income is unaffected', () {
      final insights = build([
        tx(amount: 1000, isExpense: false, date: thisMonth),
        tx(amount: 250, isExpense: true, date: thisMonth),
      ]);

      expect(insights.thisMonth.hasWindfall, isFalse);
      expect(insights.thisMonth.savingsRate, closeTo(0.75, 0.0001));
    });
  });
}
