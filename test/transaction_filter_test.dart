import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/presentation/widgets/transaction_filter_sheet.dart';

final now = DateTime(2026, 8, 28);

ExpenseModel tx(
  String title, {
  required String category,
  required DateTime date,
  double amount = 100,
  bool isExpense = true,
}) {
  return ExpenseModel(
    id: '$title$date',
    title: title,
    amount: amount,
    category: category,
    date: date,
    isExpense: isExpense,
  );
}

final ledger = [
  tx('Lunch', category: 'Food & Dining', date: DateTime(2026, 8, 27), amount: 450),
  tx('Bus fare', category: 'Transport', date: DateTime(2026, 8, 20), amount: 50),
  tx('Salary', category: 'Salary', date: DateTime(2026, 8, 1), amount: 60000, isExpense: false),
  tx('Old shoes', category: 'Shopping', date: DateTime(2026, 5, 4), amount: 3000),
  tx('July rent', category: 'Rent', date: DateTime(2026, 7, 2), amount: 15000),
];

void main() {
  group('search', () {
    test('matches the title', () {
      final results =
          const TransactionFilter().apply(ledger, query: 'lunch', now: now);
      expect(results.map((t) => t.title), ['Lunch']);
    });

    test('matches the category too', () {
      final results =
          const TransactionFilter().apply(ledger, query: 'transport', now: now);
      expect(results.map((t) => t.title), ['Bus fare']);
    });

    test('ignores case and surrounding space', () {
      final results =
          const TransactionFilter().apply(ledger, query: '  SALARY ', now: now);
      expect(results, hasLength(1));
    });

    test('an empty query keeps everything', () {
      expect(
        const TransactionFilter().apply(ledger, query: '', now: now),
        hasLength(ledger.length),
      );
    });
  });

  group('direction', () {
    test('expenses only', () {
      final results = const TransactionFilter(direction: DirectionFilter.expense)
          .apply(ledger, now: now);
      expect(results.every((t) => t.isExpense), isTrue);
      expect(results, hasLength(4));
    });

    test('income only', () {
      final results = const TransactionFilter(direction: DirectionFilter.income)
          .apply(ledger, now: now);
      expect(results.map((t) => t.title), ['Salary']);
    });
  });

  group('period', () {
    test('this month excludes earlier months', () {
      final results = const TransactionFilter(period: PeriodFilter.thisMonth)
          .apply(ledger, now: now);
      expect(results.map((t) => t.title), ['Lunch', 'Bus fare', 'Salary']);
    });

    test('last month is bounded on both sides', () {
      final results = const TransactionFilter(period: PeriodFilter.lastMonth)
          .apply(ledger, now: now);
      expect(results.map((t) => t.title), ['July rent']);
    });

    test('last 30 days counts today as day one', () {
      // 30 days back from 28 Aug reaches 30 July, so the 20 Aug bus fare is in
      // and the 2 July rent is out.
      final results = const TransactionFilter(period: PeriodFilter.last30Days)
          .apply(ledger, now: now);
      expect(results.map((t) => t.title), ['Lunch', 'Bus fare', 'Salary']);
    });

    test('this year excludes nothing from 2026', () {
      final results = const TransactionFilter(period: PeriodFilter.thisYear)
          .apply(ledger, now: now);
      expect(results, hasLength(ledger.length));
    });
  });

  group('categories', () {
    test('an empty set means every category', () {
      expect(
        const TransactionFilter().apply(ledger, now: now),
        hasLength(ledger.length),
      );
    });

    test('several categories can be selected at once', () {
      final results = const TransactionFilter(
        categories: {'Transport', 'Rent'},
      ).apply(ledger, now: now);

      expect(results.map((t) => t.title).toSet(), {'Bus fare', 'July rent'});
    });
  });

  group('sort', () {
    test('newest first is the default', () {
      final results = const TransactionFilter().apply(ledger, now: now);
      expect(results.first.title, 'Lunch');
      expect(results.last.title, 'Old shoes');
    });

    test('oldest first reverses it', () {
      final results = const TransactionFilter(sort: TransactionSort.oldest)
          .apply(ledger, now: now);
      expect(results.first.title, 'Old shoes');
    });

    test('largest and smallest order by amount', () {
      expect(
        const TransactionFilter(sort: TransactionSort.largest)
            .apply(ledger, now: now)
            .first
            .title,
        'Salary',
      );
      expect(
        const TransactionFilter(sort: TransactionSort.smallest)
            .apply(ledger, now: now)
            .first
            .title,
        'Bus fare',
      );
    });
  });

  group('combining', () {
    test('filters intersect rather than replace each other', () {
      final results = const TransactionFilter(
        direction: DirectionFilter.expense,
        period: PeriodFilter.thisMonth,
      ).apply(ledger, query: 'n', now: now);

      // Expenses, in August, whose title or category contains "n".
      // Lunch matches on title and Bus fare on "Transport". Salary is cut by
      // direction, July rent and Old shoes by period - both of which would
      // otherwise match "n" too, which is what makes this an intersection.
      expect(results.map((t) => t.title).toSet(), {'Lunch', 'Bus fare'});
    });
  });

  group('the badge count', () {
    test('a clean filter counts nothing', () {
      expect(const TransactionFilter().activeCount, 0);
      expect(const TransactionFilter().isActive, isFalse);
    });

    test('sorting alone is not counted, because it hides nothing', () {
      const sorted = TransactionFilter(sort: TransactionSort.largest);
      expect(sorted.activeCount, 0);
      expect(sorted.isActive, isFalse);
    });

    test('each narrowing choice adds one', () {
      const filter = TransactionFilter(
        direction: DirectionFilter.income,
        period: PeriodFilter.thisYear,
        categories: {'Salary'},
      );
      expect(filter.activeCount, 3);
    });
  });
}
