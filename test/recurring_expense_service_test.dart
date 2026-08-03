import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/recurring_expense_model.dart';
import 'package:smartexpense/services/recurring_expense_service.dart';

void main() {
  group('RecurringExpenseService', () {
    test('computeNextDueDate adds monthly intervals correctly', () {
      final result = RecurringExpenseService.computeNextDueDate(
        DateTime(2024, 1, 31),
        RecurringFrequency.monthly,
      );

      expect(result, DateTime(2024, 2, 29));
    });

    test('computeNextDueDate adds yearly intervals correctly', () {
      final result = RecurringExpenseService.computeNextDueDate(
        DateTime(2024, 3, 10),
        RecurringFrequency.yearly,
        1,
      );

      expect(result, DateTime(2025, 3, 10));
    });

    test('occurrencesUpTo returns every due date up to the limit', () {
      final result = RecurringExpenseService.occurrencesUpTo(
        from: DateTime(2024, 1, 1),
        upTo: DateTime(2024, 3, 15),
        frequency: RecurringFrequency.monthly,
        interval: 1,
      );

      expect(result, [
        DateTime(2024, 1, 1),
        DateTime(2024, 2, 1),
        DateTime(2024, 3, 1),
      ]);
    });

    test('buildRecurringTransactionId is deterministic', () {
      final id = RecurringExpenseService.buildRecurringTransactionId(
        'rec_123',
        DateTime(2024, 7, 24),
      );

      expect(id, 'rec_123_20240724');
    });

    test('isRecurringDue returns true for active due items', () {
      final expense = RecurringExpenseModel(
        id: '1',
        userId: 'user_1',
        title: 'Rent',
        category: 'rent',
        amount: 12000,
        currency: 'NPR',
        frequency: RecurringFrequency.monthly,
        nextDueDate: DateTime(2024, 7, 1),
        startDate: DateTime(2024, 7, 1),
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(
        RecurringExpenseService.isRecurringDue(expense, DateTime(2024, 7, 1)),
        isTrue,
      );
    });
  });
}
