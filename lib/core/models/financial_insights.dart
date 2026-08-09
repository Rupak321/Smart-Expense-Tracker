import '../utils/money_utils.dart';
import 'expense_model.dart';

/// How firm the assistant should be, decided from the numbers rather than
/// picked at random.
///
/// The assistant is a friend first, but a friend who tells you the truth when
/// the data says you are in trouble.
enum CoachStance {
  /// Nothing notable. Warm and relaxed.
  calm,

  /// Saving well. Celebrate it, keep the momentum.
  encouraging,

  /// Something is drifting — thin savings, a category climbing.
  watchful,

  /// Spending exceeds income, or the balance is going backwards. Be direct.
  strict,
}

extension CoachStanceInfo on CoachStance {
  String get label => switch (this) {
    CoachStance.calm => 'Steady',
    CoachStance.encouraging => 'On track',
    CoachStance.watchful => 'Watch it',
    CoachStance.strict => 'Action needed',
  };

  /// Instruction handed to the model so tone follows the data.
  String get directive => switch (this) {
    CoachStance.calm =>
      'Tone: relaxed and friendly. Nothing is on fire. Do not manufacture '
          'alarm or invent problems that the numbers do not show.',
    CoachStance.encouraging =>
      'Tone: warm and genuinely pleased. They are saving well — say so '
          'specifically, name the number, then help them keep it going.',
    CoachStance.watchful =>
      'Tone: friendly but honest. Point at the specific thing that is '
          'drifting, with its number, and give one concrete correction. Do '
          'not lecture.',
    CoachStance.strict =>
      'Tone: direct and serious, still on their side. Lead with the hard '
          'number. Do not soften it with jokes or filler. Name the single '
          'biggest leak and the exact change that fixes it. Firm, never '
          'insulting, never shaming.',
  };
}

/// Income and spending for one calendar month.
class MonthlySnapshot {
  final DateTime month;
  final int incomePaisa;
  final int expensePaisa;
  final int transactionCount;

  const MonthlySnapshot({
    required this.month,
    required this.incomePaisa,
    required this.expensePaisa,
    required this.transactionCount,
  });

  /// The income-minus-expenditure difference: positive means money kept.
  int get netPaisa => incomePaisa - expensePaisa;

  bool get isOverspending => expensePaisa > incomePaisa;

  bool get hasActivity => transactionCount > 0;

  /// Share of income kept, e.g. 0.25 for 25%. Null when there is no income to
  /// measure against — a rate is meaningless then.
  double? get savingsRate {
    if (incomePaisa <= 0) return null;
    return netPaisa / incomePaisa;
  }
}

/// One spending category this month, compared with last month.
class CategoryInsight {
  final String label;
  final int paisa;
  final int previousPaisa;

  /// Share of this month's total spending, 0..1.
  final double share;

  const CategoryInsight({
    required this.label,
    required this.paisa,
    required this.previousPaisa,
    required this.share,
  });

  int get deltaPaisa => paisa - previousPaisa;

  bool get isNew => previousPaisa == 0 && paisa > 0;

  /// Growth vs last month, e.g. 0.6 for +60%. Null when there is no baseline.
  double? get changeRatio {
    if (previousPaisa <= 0) return null;
    return deltaPaisa / previousPaisa;
  }
}

/// A known future outflow — a recurring expense or a bill reminder.
class UpcomingCommitment {
  final String title;
  final int paisa;
  final DateTime dueDate;

  /// 'recurring' or 'bill'.
  final String source;

  const UpcomingCommitment({
    required this.title,
    required this.paisa,
    required this.dueDate,
    required this.source,
  });
}

/// The complete, exact financial picture, computed in Dart.
///
/// Everything here is arithmetic done locally over the full transaction
/// history. The language model is handed these finished numbers and never asked
/// to compute its own — small models are unreliable at arithmetic, and the
/// previous prompt let one sum a truncated 18-row window and call the result a
/// lifetime total.
class FinancialInsights {
  final int totalIncomePaisa;
  final int totalExpensePaisa;
  final int transactionCount;
  final DateTime? earliestDate;
  final DateTime generatedAt;

  final MonthlySnapshot thisMonth;
  final MonthlySnapshot lastMonth;

  final List<CategoryInsight> topCategories;
  final List<ExpenseModel> biggestExpensesThisMonth;

  final int last30DaysExpensePaisa;
  final int committedMonthlyPaisa;
  final List<UpcomingCommitment> upcoming;

  final CoachStance stance;
  final List<String> concerns;
  final List<String> wins;

  const FinancialInsights({
    required this.totalIncomePaisa,
    required this.totalExpensePaisa,
    required this.transactionCount,
    required this.earliestDate,
    required this.generatedAt,
    required this.thisMonth,
    required this.lastMonth,
    required this.topCategories,
    required this.biggestExpensesThisMonth,
    required this.last30DaysExpensePaisa,
    required this.committedMonthlyPaisa,
    required this.upcoming,
    required this.stance,
    required this.concerns,
    required this.wins,
  });

  /// All-time income minus all-time expenditure.
  int get balancePaisa => totalIncomePaisa - totalExpensePaisa;

  bool get hasData => transactionCount > 0;

  /// Average spend per day over the last 30 days.
  int get dailyBurnPaisa => (last30DaysExpensePaisa / 30).round();

  /// How many days the current balance lasts at the current burn rate.
  /// Null when nothing is being spent or the balance is already negative.
  int? get runwayDays {
    if (dailyBurnPaisa <= 0 || balancePaisa <= 0) return null;
    return (balancePaisa / dailyBurnPaisa).floor();
  }

  /// Where this month's spending lands if the current pace holds.
  int? get projectedMonthEndExpensePaisa {
    final daysElapsed = generatedAt.day;
    if (daysElapsed <= 0 || thisMonth.expensePaisa <= 0) return null;
    final daysInMonth = DateTime(
      generatedAt.year,
      generatedAt.month + 1,
      0,
    ).day;
    return (thisMonth.expensePaisa / daysElapsed * daysInMonth).round();
  }

  /// Spending change vs last month, e.g. 0.2 for +20%.
  double? get spendingChangeRatio {
    if (lastMonth.expensePaisa <= 0) return null;
    return (thisMonth.expensePaisa - lastMonth.expensePaisa) /
        lastMonth.expensePaisa;
  }

  /// One-line status for the chat header.
  String get headline {
    if (!hasData) return 'No transactions yet';
    final net = thisMonth.netPaisa;
    if (thisMonth.isOverspending) {
      return 'Over by ${MoneyUtils.formatCompactPaisa(net.abs())} this month';
    }
    if (net > 0) {
      return 'Kept ${MoneyUtils.formatCompactPaisa(net)} this month';
    }
    return 'Breaking even this month';
  }
}
