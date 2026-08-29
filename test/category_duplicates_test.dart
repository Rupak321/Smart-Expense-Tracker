import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_category.dart';
import 'package:smartexpense/services/category_service.dart';

final now = DateTime(2026, 8, 15);

ExpenseCategory cat(
  String name, {
  CategoryKind kind = CategoryKind.expense,
  bool isSystem = false,
}) {
  return ExpenseCategory(
    id: name,
    name: name,
    kind: kind,
    iconKey: 'category',
    colorIndex: 0,
    createdAt: now,
    isSystem: isSystem,
  );
}

void main() {
  group('merge direction', () {
    test('keeps the seeded category and absorbs the improvised one', () {
      // On device this proposed "Shopping -> Shopping - Clothes", folding the
      // tidy seeded name into the model's improvised one. Backwards.
      final suggestions = CategoryService.findDuplicates([
        cat('Shopping', isSystem: true),
        cat('Shopping - Clothes'),
      ]);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.from.name, 'Shopping - Clothes');
      expect(suggestions.single.into.name, 'Shopping');
    });

    test('direction does not depend on list order', () {
      final reversed = CategoryService.findDuplicates([
        cat('Shopping - Clothes'),
        cat('Shopping', isSystem: true),
      ]);

      expect(reversed.single.from.name, 'Shopping - Clothes');
      expect(reversed.single.into.name, 'Shopping');
    });

    test('with no seeded side, the more used category survives', () {
      // Both user-created, so the seeded rule cannot decide. The longer name
      // is the busier one here, which is what isolates usage from the
      // shorter-name tiebreak below.
      final suggestions = CategoryService.findDuplicates(
        [cat('Food & Dining'), cat('Food - Restaurant')],
        usage: const {
          'Food & Dining': CategoryUsage(count: 1, paisa: 100),
          'Food - Restaurant': CategoryUsage(count: 9, paisa: 900),
        },
      );

      expect(suggestions.single.from.name, 'Food & Dining');
      expect(suggestions.single.into.name, 'Food - Restaurant');
    });

    test('with no usage either, the shorter name survives', () {
      final suggestions = CategoryService.findDuplicates([
        cat('Food - Miscellaneous Items'),
        cat('Food'),
      ]);

      expect(suggestions.single.into.name, 'Food');
    });
  });

  group('multiple duplicates of the same target', () {
    test('every variant folds into the canonical category', () {
      // The first version locked the target as soon as one duplicate claimed
      // it, so "Food - Restaurant" was silently left behind.
      final suggestions = CategoryService.findDuplicates([
        cat('Food & Dining', isSystem: true),
        cat('Food - Miscellaneous'),
        cat('Food - Restaurant'),
      ]);

      expect(suggestions, hasLength(2));
      expect(
        suggestions.map((s) => s.from.name).toSet(),
        {'Food - Miscellaneous', 'Food - Restaurant'},
      );
      expect(
        suggestions.every((s) => s.into.name == 'Food & Dining'),
        isTrue,
      );
    });

    test('a category is never both absorbed and a target', () {
      final suggestions = CategoryService.findDuplicates([
        cat('Food & Dining', isSystem: true),
        cat('Food - Miscellaneous'),
        cat('Food - Restaurant'),
        cat('Salary', kind: CategoryKind.income, isSystem: true),
        cat('Income - Salary', kind: CategoryKind.income),
      ]);

      final absorbed = suggestions.map((s) => s.from.id).toSet();
      final targets = suggestions.map((s) => s.into.id).toSet();
      expect(absorbed.intersection(targets), isEmpty);
    });
  });

  group('what it leaves alone', () {
    test('unrelated categories are not proposed', () {
      final suggestions = CategoryService.findDuplicates([
        cat('Food & Dining', isSystem: true),
        cat('Transport', isSystem: true),
        cat('Rent', isSystem: true),
      ]);

      expect(suggestions, isEmpty);
    });

    test('the fallback is never merged away or merged into', () {
      final suggestions = CategoryService.findDuplicates([
        cat(ExpenseCategory.fallbackName, kind: CategoryKind.both),
        cat('Other Stuff'),
      ]);

      expect(
        suggestions.any(
          (s) =>
              s.from.isFallback ||
              s.into.name == ExpenseCategory.fallbackName,
        ),
        isFalse,
      );
    });

    test('an empty vocabulary yields nothing', () {
      expect(CategoryService.findDuplicates(const []), isEmpty);
    });
  });

  group('the real vocabulary from the device', () {
    test('proposes the right four merges in the right direction', () {
      final vocabulary = [
        ...ExpenseCategory.defaults(now),
        cat('Food - Restaurant'),
        cat('Food - Miscellaneous'),
        cat('Shopping - Clothes'),
        cat('Shopping - Gift'),
        cat('Income - Salary', kind: CategoryKind.income),
        cat('Income - Family', kind: CategoryKind.income),
        cat('Cash - Personal'),
      ];

      final suggestions = CategoryService.findDuplicates(vocabulary);

      // Nothing seeded should ever be the one that disappears.
      expect(suggestions.any((s) => s.from.isSystem), isFalse);

      final byName = {for (final s in suggestions) s.from.name: s.into.name};
      expect(byName['Food - Restaurant'], 'Food & Dining');
      expect(byName['Food - Miscellaneous'], 'Food & Dining');
      expect(byName['Shopping - Clothes'], 'Shopping');
      expect(byName['Income - Salary'], 'Salary');
      expect(byName['Income - Family'], 'Family & Gifts');
    });
  });
}
