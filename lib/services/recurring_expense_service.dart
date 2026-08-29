import 'dart:math' as math;

import '../core/models/recurring_expense_model.dart';

class RecurringExpenseService {
  const RecurringExpenseService();

  static DateTime computeNextDueDate(
    DateTime currentDate,
    RecurringFrequency frequency, [
    int interval = 1,
  ]) {
    switch (frequency) {
      case RecurringFrequency.daily:
        return currentDate.add(Duration(days: interval));
      case RecurringFrequency.weekly:
        return currentDate.add(Duration(days: 7 * interval));
      case RecurringFrequency.monthly:
        return _addMonths(currentDate, interval);
      case RecurringFrequency.yearly:
        return DateTime(
          currentDate.year + interval,
          currentDate.month,
          currentDate.day,
        );
    }
  }

  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + (totalMonths ~/ 12);
    final month = (totalMonths % 12) + 1;
    final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
    final safeDay = math.min(date.day, lastDayOfTargetMonth);
    return DateTime(year, month, safeDay);
  }

  static List<DateTime> occurrencesUpTo({
    required DateTime from,
    required DateTime upTo,
    required RecurringFrequency frequency,
    required int interval,
    DateTime? endDate,
  }) {
    final result = <DateTime>[];
    var cursor = from;

    while (!cursor.isAfter(upTo)) {
      if (endDate != null && cursor.isAfter(endDate)) {
        break;
      }
      result.add(cursor);
      cursor = computeNextDueDate(cursor, frequency, interval);
    }

    return result;
  }

  static String buildRecurringTransactionId(String recurringId, DateTime date) {
    return '${recurringId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  static bool isRecurringDue(RecurringExpenseModel expense, DateTime now) {
    if (expense.status != RecurringStatus.active) {
      return false;
    }
    if (expense.endDate != null && expense.nextDueDate.isAfter(expense.endDate!)) {
      return false;
    }
    return !expense.nextDueDate.isAfter(now);
  }

  static List<RecurringExpenseModel> getDueExpenses(
    List<RecurringExpenseModel> expenses,
    DateTime now,
  ) {
    return expenses
        .where((expense) => isRecurringDue(expense, now))
        .toList();
  }
}
