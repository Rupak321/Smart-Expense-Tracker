import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/services/user_data_service.dart';

/// The stored direction is the only thing that decides income vs expense.
///
/// A previous version re-derived it by scanning the title and category for
/// words like "gift" or "business", so a recorded expense came back as income
/// and landed on the wrong side of the balance, the savings rate, every chart
/// and the figures the assistant was given to talk about.
void main() {
  Map<String, dynamic> stored({
    required String title,
    required String category,
    required bool isExpense,
  }) {
    return {
      'title': title,
      'amount': 5000.0,
      'category': category,
      'date': Timestamp.fromDate(DateTime(2026, 8, 28)),
      'isExpense': isExpense,
    };
  }

  group('an expense stays an expense', () {
    // Every one of these was silently flipped to income by the old classifier.
    const wordsThatUsedToFlipIt = [
      'Gift',
      'Business cards',
      'Investment app subscription',
      'Refund fee',
      'Allowance for the kids',
      'Bonus pack of coffee',
      'Commission paid to agent',
      'Received parcel charge',
    ];

    for (final title in wordsThatUsedToFlipIt) {
      test('"$title"', () {
        final result = UserDataService.expenseFromMap(
          'id',
          stored(title: title, category: 'Other', isExpense: true),
        );
        expect(result.isExpense, isTrue, reason: '$title must stay an expense');
      });
    }

    test('even when the category name carries the trigger word', () {
      // The live case: an expense filed under "Shopping - Gift" displayed as
      // "+ Rs. 5,000" because the category was searched too.
      final result = UserDataService.expenseFromMap(
        'id',
        stored(title: 'Gift', category: 'Shopping - Gift', isExpense: true),
      );

      expect(result.isExpense, isTrue);
    });
  });

  test('income stored as income stays income', () {
    final result = UserDataService.expenseFromMap(
      'id',
      stored(title: 'Office Salary', category: 'Salary', isExpense: false),
    );

    expect(result.isExpense, isFalse);
  });

  test('a title with no signal words is respected in both directions', () {
    for (final isExpense in [true, false]) {
      final result = UserDataService.expenseFromMap(
        'id',
        stored(title: 'Something', category: 'Other', isExpense: isExpense),
      );
      expect(result.isExpense, isExpense);
    }
  });

  test('a document missing the field is treated as an expense', () {
    final result = UserDataService.expenseFromMap('id', const {
      'title': 'Legacy row',
      'amount': 100.0,
    });

    expect(result.isExpense, isTrue);
    expect(result.category, 'Other');
  });
}
