import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/categories/category_matcher.dart';
import 'package:smartexpense/core/models/expense_category.dart';

final now = DateTime(2026, 8, 15);
final defaults = ExpenseCategory.defaults(now);

CategoryMatch match(String name, {bool isExpense = true}) {
  return CategoryMatcher.match(
    rawName: name,
    categories: defaults,
    isExpense: isExpense,
  );
}

void main() {
  group('exact matching', () {
    test('ignores case, spacing and punctuation', () {
      for (final variant in [
        'Food & Dining',
        'food & dining',
        'FOOD AND DINING',
        'food-dining',
        '  Food   Dining  ',
      ]) {
        final result = match(variant);
        expect(result.category?.name, 'Food & Dining', reason: variant);
        expect(result.isNew, isFalse, reason: variant);
      }
    });
  });

  group('alias matching', () {
    test('folds the real-world duplicates onto one category', () {
      // These two became separate categories in production and split food
      // spending across two slices in analytics.
      expect(match('Food - Restaurant').category?.name, 'Food & Dining');
      expect(match('Food - Miscellaneous').category?.name, 'Food & Dining');
      expect(
        match('Food - Restaurant').reason,
        CategoryMatchReason.alias,
      );
    });

    test('maps common synonyms', () {
      expect(match('Restaurant').category?.name, 'Food & Dining');
      expect(match('coffee').category?.name, 'Food & Dining');
      expect(match('Taxi').category?.name, 'Transport');
      expect(match('Electricity').category?.name, 'Bills & Utilities');
      expect(match('Medicine').category?.name, 'Health');
      expect(match('Shopping - Clothes').category?.name, 'Shopping');
    });

    test('maps income synonyms', () {
      expect(match('Payroll', isExpense: false).category?.name, 'Salary');
      expect(
        match('Income - Salary', isExpense: false).category?.name,
        'Salary',
      );
      expect(
        match('Cashback', isExpense: false).category?.name,
        'Refunds',
      );
      expect(
        match('Mom', isExpense: false).category?.name,
        'Family & Gifts',
      );
    });
  });

  group('fuzzy matching', () {
    test('absorbs small spelling differences', () {
      expect(match('Foods').category?.name, 'Food & Dining');
      expect(match('Groceriess').category?.name, 'Groceries');
      expect(match('Transportation').category?.name, 'Transport');
    });

    test('absorbs reworded variants', () {
      expect(match('Food and Dining').category?.name, 'Food & Dining');
      expect(match('Bills and Utilities').category?.name, 'Bills & Utilities');
    });
  });

  group('direction awareness', () {
    test('an expense never lands in an income-only category', () {
      final result = match('Salary', isExpense: true);
      expect(result.category?.name, isNot('Salary'));
    });

    test('income can use an income category', () {
      expect(match('Salary', isExpense: false).category?.name, 'Salary');
    });

    test('a both-kind category is available to either direction', () {
      expect(match('Gift', isExpense: false).category?.name, 'Family & Gifts');
      expect(match('Gift', isExpense: true).category?.name, 'Family & Gifts');
    });
  });

  group('novel categories', () {
    test('genuinely new names are proposed, not forced into a match', () {
      final result = match('Pet Care');
      expect(result.isNew, isTrue);
      expect(result.reason, CategoryMatchReason.novel);
      expect(result.proposedName, 'Pet Care');
      expect(result.category, isNull);
    });

    test('proposed names are tidied', () {
      expect(match('  pet   care  ').proposedName, 'Pet Care');
      expect(match('gym membership').proposedName, 'Gym Membership');
    });

    test('unrelated names do not collapse onto each other', () {
      // Guards against an over-eager threshold quietly merging real
      // categories.
      expect(match('Charity').isNew, isTrue);
      expect(match('Insurance').isNew, isTrue);
      expect(match('Pet Care').isNew, isTrue);
    });
  });

  group('empty and fallback', () {
    test('blank input falls back to Other rather than creating a category', () {
      for (final blank in ['', '   ', '!!!']) {
        final result = match(blank);
        expect(result.category?.name, ExpenseCategory.fallbackName,
            reason: 'input: "$blank"');
        expect(result.isNew, isFalse, reason: 'input: "$blank"');
      }
    });

    test('resolvedName always yields something usable', () {
      expect(match('').resolvedName, 'Other');
      expect(match('Pet Care').resolvedName, 'Pet Care');
      expect(match('Restaurant').resolvedName, 'Food & Dining');
    });
  });

  group('against a user vocabulary rather than the defaults', () {
    final custom = [
      ExpenseCategory(
        id: '1',
        name: 'Momos',
        kind: CategoryKind.expense,
        iconKey: 'restaurant',
        colorIndex: 0,
        createdAt: now,
      ),
      ExpenseCategory(
        id: '2',
        name: ExpenseCategory.fallbackName,
        kind: CategoryKind.both,
        iconKey: 'category',
        colorIndex: 1,
        createdAt: now,
      ),
    ];

    test('reuses a user-created category exactly', () {
      final result = CategoryMatcher.match(
        rawName: 'momos',
        categories: custom,
        isExpense: true,
      );
      expect(result.category?.name, 'Momos');
    });

    test('an alias with no matching category is treated as new', () {
      // 'Restaurant' maps to Food & Dining, which this user does not have.
      final result = CategoryMatcher.match(
        rawName: 'Restaurant',
        categories: custom,
        isExpense: true,
      );
      expect(result.isNew, isTrue);
      expect(result.proposedName, 'Restaurant');
    });
  });
}
