import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/budget.dart';
import 'package:smartexpense/core/models/expense_model.dart';

/// 15 August: the month is exactly half gone, which makes the pace maths
/// easy to reason about by hand.
final midMonth = DateTime(2026, 8, 15);

Budget budget(String? category, int limitRupees) {
  return Budget(
    id: category ?? 'overall',
    category: category,
    limitPaisa: limitRupees * 100,
    createdAt: DateTime(2026, 8, 1),
  );
}

ExpenseModel spend(
  String category,
  int rupees, {
  int day = 5,
  int month = 8,
  bool isExpense = true,
}) {
  return ExpenseModel(
    id: '$category$day$month$rupees',
    title: category,
    amount: rupees.toDouble(),
    category: category,
    date: DateTime(2026, month, day),
    isExpense: isExpense,
  );
}

List<BudgetProgress> evaluate(
  List<Budget> budgets,
  List<ExpenseModel> transactions, {
  DateTime? now,
}) {
  return BudgetCalculator.evaluate(
    budgets: budgets,
    transactions: transactions,
    now: now ?? midMonth,
  );
}

void main() {
  group('what counts towards a budget', () {
    test('only the named category', () {
      final result = evaluate(
        [budget('Food & Dining', 8000)],
        [spend('Food & Dining', 2000), spend('Transport', 5000)],
      );

      expect(result.single.spentPaisa, 2000 * 100);
    });

    test('an overall budget counts every category', () {
      final result = evaluate(
        [budget(null, 20000)],
        [spend('Food & Dining', 2000), spend('Transport', 5000)],
      );

      expect(result.single.spentPaisa, 7000 * 100);
    });

    test('income is never counted as spending', () {
      final result = evaluate(
        [budget(null, 20000)],
        [
          spend('Food & Dining', 2000),
          spend('Salary', 60000, isExpense: false),
        ],
      );

      expect(result.single.spentPaisa, 2000 * 100);
    });

    test('other months are excluded', () {
      final result = evaluate(
        [budget('Food & Dining', 8000)],
        [
          spend('Food & Dining', 2000, month: 8),
          spend('Food & Dining', 9999, month: 7),
          spend('Food & Dining', 9999, month: 9),
        ],
      );

      expect(result.single.spentPaisa, 2000 * 100);
    });

    test('a budget with no matching spending reads zero, not an error', () {
      final result = evaluate([budget('Rent', 15000)], []);

      expect(result.single.spentPaisa, 0);
      expect(result.single.health, BudgetHealth.comfortable);
    });
  });

  group('health', () {
    test('comfortable while both the total and the pace are fine', () {
      // Half the month gone, a fifth of the budget used.
      final result = evaluate(
        [budget('Food & Dining', 10000)],
        [spend('Food & Dining', 2000)],
      );

      expect(result.single.health, BudgetHealth.comfortable);
      expect(result.single.isOverspent, isFalse);
    });

    test('at risk when the pace overshoots but the limit still holds', () {
      // 6,000 of 10,000 by the 15th projects to about 12,400 by month end.
      final result = evaluate(
        [budget('Food & Dining', 10000)],
        [spend('Food & Dining', 6000)],
      );

      final progress = result.single;
      expect(progress.isOverspent, isFalse);
      expect(progress.isOnTrackToOverspend, isTrue);
      expect(progress.health, BudgetHealth.atRisk);
      expect(progress.projectedPaisa, greaterThan(progress.limitPaisa));
    });

    test('over once the limit is actually crossed', () {
      final result = evaluate(
        [budget('Food & Dining', 5000)],
        [spend('Food & Dining', 6000)],
      );

      final progress = result.single;
      expect(progress.health, BudgetHealth.over);
      expect(progress.isOverspent, isTrue);
      // Already over, so it is not also reported as heading there.
      expect(progress.isOnTrackToOverspend, isFalse);
      expect(progress.remainingPaisa, -1000 * 100);
    });

    test('tight near the ceiling even when the pace has settled', () {
      // Spent on the 1st and nothing since, so the projection is calm, but
      // 90% of the budget is gone with half the month left.
      final result = evaluate(
        [budget('Food & Dining', 10000)],
        [spend('Food & Dining', 9000, day: 1)],
        now: DateTime(2026, 8, 28),
      );

      expect(result.single.health, BudgetHealth.tight);
    });
  });

  group('the numbers shown to the user', () {
    test('the bar clamps at full even when overspent', () {
      final result = evaluate(
        [budget('Food & Dining', 1000)],
        [spend('Food & Dining', 5000)],
      );

      expect(result.single.ratio, greaterThan(1));
      expect(result.single.barValue, 1.0);
    });

    test('the safe daily allowance divides what is left by days remaining', () {
      // 8,000 left on the 15th of a 31 day month leaves 16 days.
      final result = evaluate(
        [budget('Food & Dining', 10000)],
        [spend('Food & Dining', 2000)],
      );

      expect(result.single.safeDailyPaisa, (8000 * 100) ~/ 16);
    });

    test('no daily allowance once the budget is spent', () {
      final result = evaluate(
        [budget('Food & Dining', 1000)],
        [spend('Food & Dining', 5000)],
      );

      expect(result.single.safeDailyPaisa, 0);
    });

    test('a zero limit does not divide by zero', () {
      final result = evaluate(
        [budget('Food & Dining', 0)],
        [spend('Food & Dining', 100)],
      );

      expect(result.single.ratio, 0);
      expect(result.single.barValue, 0);
    });
  });

  test('the worst budget is listed first', () {
    final result = evaluate(
      [
        budget('Rent', 20000),
        budget('Food & Dining', 5000),
        budget('Transport', 4000),
      ],
      [
        spend('Rent', 1000),
        spend('Food & Dining', 6000),
        spend('Transport', 2000),
      ],
    );

    expect(result.map((p) => p.budget.label).toList(), [
      'Food & Dining',
      'Transport',
      'Rent',
    ]);
  });

  test('a budget survives the round trip through storage', () {
    final original = budget('Food & Dining', 8000);
    final restored = Budget.fromMap(original.id, original.toMap());

    expect(restored.category, original.category);
    expect(restored.limitPaisa, original.limitPaisa);
    expect(restored.isOverall, isFalse);

    final overall = Budget.fromMap('x', budget(null, 5000).toMap());
    expect(overall.isOverall, isTrue);
    expect(overall.label, 'Everything');
  });
}
