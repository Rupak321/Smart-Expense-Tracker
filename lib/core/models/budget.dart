import 'expense_model.dart';

/// A monthly spending ceiling, either for one category or for everything.
///
/// The assistant has always been able to talk about budgets, but until now
/// there was nowhere to record one, so its advice could never be checked
/// against a number the user had actually committed to.
class Budget {
  final String id;

  /// The category this caps, or null when it caps total monthly spending.
  final String? category;

  final int limitPaisa;
  final DateTime createdAt;

  const Budget({
    required this.id,
    required this.category,
    required this.limitPaisa,
    required this.createdAt,
  });

  bool get isOverall => category == null;

  String get label => category ?? 'Everything';

  Budget copyWith({String? category, int? limitPaisa, bool clearCategory = false}) {
    return Budget(
      id: id,
      category: clearCategory ? null : (category ?? this.category),
      limitPaisa: limitPaisa ?? this.limitPaisa,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'limitPaisa': limitPaisa,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static Budget fromMap(String id, Map<String, dynamic> data) {
    return Budget(
      id: id,
      category: data['category'] as String?,
      limitPaisa: (data['limitPaisa'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// How a budget is doing in a given month.
class BudgetProgress {
  final Budget budget;
  final int spentPaisa;

  /// Days already counted, including today.
  final int daysElapsed;
  final int daysInMonth;

  const BudgetProgress({
    required this.budget,
    required this.spentPaisa,
    required this.daysElapsed,
    required this.daysInMonth,
  });

  int get limitPaisa => budget.limitPaisa;

  int get remainingPaisa => limitPaisa - spentPaisa;

  bool get isOverspent => spentPaisa > limitPaisa;

  /// Share of the budget used, uncapped so overspending stays visible.
  double get ratio => limitPaisa <= 0 ? 0 : spentPaisa / limitPaisa;

  /// Clamped to 1 for drawing a progress bar.
  double get barValue => ratio.clamp(0.0, 1.0);

  /// What the month ends at if the current pace holds.
  int get projectedPaisa {
    if (daysElapsed <= 0) return 0;
    return (spentPaisa / daysElapsed * daysInMonth).round();
  }

  /// True when today's pace ends the month over the limit, even though the
  /// limit has not been crossed yet. This is the warning worth giving early.
  bool get isOnTrackToOverspend => !isOverspent && projectedPaisa > limitPaisa;

  /// What could still be spent each remaining day without going over.
  int get safeDailyPaisa {
    final daysLeft = daysInMonth - daysElapsed;
    if (daysLeft <= 0 || remainingPaisa <= 0) return 0;
    return remainingPaisa ~/ daysLeft;
  }

  BudgetHealth get health {
    if (isOverspent) return BudgetHealth.over;
    if (isOnTrackToOverspend) return BudgetHealth.atRisk;
    if (ratio >= 0.8) return BudgetHealth.tight;
    return BudgetHealth.comfortable;
  }
}

enum BudgetHealth { comfortable, tight, atRisk, over }

/// Measures budgets against a month of transactions.
///
/// Pure, so budget behaviour is testable without Firestore or a widget.
class BudgetCalculator {
  const BudgetCalculator._();

  static List<BudgetProgress> evaluate({
    required List<Budget> budgets,
    required List<ExpenseModel> transactions,
    required DateTime now,
  }) {
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final daysInMonth = nextMonth.difference(monthStart).inDays;

    final thisMonth = transactions.where((transaction) {
      return transaction.countsAsExpense &&
          !transaction.date.isBefore(monthStart) &&
          transaction.date.isBefore(nextMonth);
    }).toList();

    final results = budgets.map((budget) {
      final relevant = budget.isOverall
          ? thisMonth
          : thisMonth.where((t) => t.category == budget.category);
      final spent = relevant.fold(0, (sum, t) => sum + t.amountPaisa);

      return BudgetProgress(
        budget: budget,
        spentPaisa: spent,
        daysElapsed: now.day,
        daysInMonth: daysInMonth,
      );
    }).toList();

    // Worst first, so what needs attention is what the user sees.
    results.sort((a, b) => b.ratio.compareTo(a.ratio));
    return results;
  }
}
