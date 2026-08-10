import '../utils/money_utils.dart';
import 'expense_model.dart';

/// The reporting window the user picked.
///
/// The old flow passed an ambiguous `forMonths` int (0, 1, 3 or null) that was
/// then never used to filter anything, so every option produced an identical
/// all-time report. A closed set of periods that each resolve to a real date
/// range removes that whole class of bug.
enum ReportPeriod {
  last7Days,
  last30Days,
  monthToDate,
  lastMonth,
  last3Months,
  thisYear,
  allTime,
}

extension ReportPeriodInfo on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.last7Days => 'Last 7 days',
    ReportPeriod.last30Days => 'Last 30 days',
    ReportPeriod.monthToDate => 'Month to date',
    ReportPeriod.lastMonth => 'Last month',
    ReportPeriod.last3Months => 'Last 3 months',
    ReportPeriod.thisYear => 'This year',
    ReportPeriod.allTime => 'All time',
  };

  String get description => switch (this) {
    ReportPeriod.last7Days => 'A quick weekly check',
    ReportPeriod.last30Days => 'A rolling month of activity',
    ReportPeriod.monthToDate => 'This calendar month so far',
    ReportPeriod.lastMonth => 'The previous calendar month, complete',
    ReportPeriod.last3Months => 'A quarterly review',
    ReportPeriod.thisYear => 'Year to date',
    ReportPeriod.allTime => 'Everything you have recorded',
  };

  /// Inclusive start of the window. Null means "no lower bound".
  DateTime? startFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ReportPeriod.last7Days => today.subtract(const Duration(days: 6)),
      ReportPeriod.last30Days => today.subtract(const Duration(days: 29)),
      ReportPeriod.monthToDate => DateTime(now.year, now.month),
      ReportPeriod.lastMonth => DateTime(now.year, now.month - 1),
      ReportPeriod.last3Months => DateTime(now.year, now.month - 2),
      ReportPeriod.thisYear => DateTime(now.year),
      ReportPeriod.allTime => null,
    };
  }

  /// Exclusive end of the window. Null means "up to now".
  DateTime? endBefore(DateTime now) {
    return switch (this) {
      // The only period that closes before today.
      ReportPeriod.lastMonth => DateTime(now.year, now.month),
      _ => null,
    };
  }

  bool contains(DateTime date, DateTime now) {
    final start = startFrom(now);
    final end = endBefore(now);
    if (start != null && date.isBefore(start)) return false;
    if (end != null && !date.isBefore(end)) return false;
    return true;
  }

  /// The equally long window immediately before this one, used for the
  /// "vs previous period" comparison. Null where a comparison is meaningless.
  DateTimeRange? previousRange(DateTime now) {
    final start = startFrom(now);
    if (start == null) return null;
    final end = endBefore(now) ?? now;
    final span = end.difference(start);
    if (span.inDays <= 0) return null;
    return DateTimeRange(start: start.subtract(span), end: start);
  }
}

/// Minimal date range holder so this model stays free of Flutter imports.
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  const DateTimeRange({required this.start, required this.end});

  bool contains(DateTime date) {
    return !date.isBefore(start) && date.isBefore(end);
  }
}

/// One spending category within the report window.
class ReportCategory {
  final String label;
  final int paisa;
  final int transactionCount;

  /// Share of total spending in the window, 0..1.
  final double share;

  const ReportCategory({
    required this.label,
    required this.paisa,
    required this.transactionCount,
    required this.share,
  });
}

/// Income and spending for one calendar month inside the window.
class ReportMonth {
  final DateTime month;
  final int incomePaisa;
  final int expensePaisa;

  const ReportMonth({
    required this.month,
    required this.incomePaisa,
    required this.expensePaisa,
  });

  int get netPaisa => incomePaisa - expensePaisa;

  String get shortLabel {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }
}

/// A fully computed report, ready to render to screen or to PDF.
///
/// Every figure here is exact arithmetic over the filtered transactions. The AI
/// narrative is an optional extra layer on top — the report is complete and
/// useful without it, which also means it still works with no API key.
class FinancialReport {
  final ReportPeriod period;
  final DateTime generatedAt;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  final int incomePaisa;
  final int expensePaisa;
  final int incomeCount;
  final int expenseCount;

  final List<ReportCategory> categories;
  final List<ReportMonth> months;
  final List<ExpenseModel> topExpenses;
  final List<ExpenseModel> topIncome;

  /// Same figures for the equally long window before this one.
  final int? previousExpensePaisa;
  final int? previousIncomePaisa;

  final List<String> observations;

  /// Optional AI-written commentary. Null when unavailable or not requested.
  final String? narrative;

  const FinancialReport({
    required this.period,
    required this.generatedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.incomePaisa,
    required this.expensePaisa,
    required this.incomeCount,
    required this.expenseCount,
    required this.categories,
    required this.months,
    required this.topExpenses,
    required this.topIncome,
    required this.previousExpensePaisa,
    required this.previousIncomePaisa,
    required this.observations,
    this.narrative,
  });

  FinancialReport copyWith({String? narrative}) {
    return FinancialReport(
      period: period,
      generatedAt: generatedAt,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      incomePaisa: incomePaisa,
      expensePaisa: expensePaisa,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      categories: categories,
      months: months,
      topExpenses: topExpenses,
      topIncome: topIncome,
      previousExpensePaisa: previousExpensePaisa,
      previousIncomePaisa: previousIncomePaisa,
      observations: observations,
      narrative: narrative ?? this.narrative,
    );
  }

  int get transactionCount => incomeCount + expenseCount;

  bool get hasData => transactionCount > 0;

  int get netPaisa => incomePaisa - expensePaisa;

  /// Share of income kept. Null when there is no income to measure against.
  double? get savingsRate {
    if (incomePaisa <= 0) return null;
    return netPaisa / incomePaisa;
  }

  /// Spending change vs the previous equally long window.
  double? get expenseChangeRatio {
    final previous = previousExpensePaisa;
    if (previous == null || previous <= 0) return null;
    return (expensePaisa - previous) / previous;
  }

  /// Number of days the window actually covers.
  int get dayCount {
    final start = rangeStart;
    final end = rangeEnd ?? generatedAt;
    if (start == null) return 0;
    final days = end.difference(start).inDays + 1;
    return days < 1 ? 1 : days;
  }

  int get averageDailyExpensePaisa {
    final days = dayCount;
    if (days <= 0) return 0;
    return _toWholeRupees((expensePaisa / days).round());
  }

  int get averageExpensePerTransactionPaisa {
    if (expenseCount <= 0) return 0;
    return _toWholeRupees((expensePaisa / expenseCount).round());
  }

  /// Averages are estimates, so they are shown to the rupee.
  /// "Rs. 3,169.44 per day" reads like a measured fact rather than a mean.
  static int _toWholeRupees(int paisa) => (paisa / 100).round() * 100;

  ReportCategory? get largestCategory =>
      categories.isEmpty ? null : categories.first;

  ExpenseModel? get largestExpense =>
      topExpenses.isEmpty ? null : topExpenses.first;

  /// Human range for the report header, e.g. "1 Jul 2026 - 9 Aug 2026".
  String get rangeLabel {
    final start = rangeStart;
    final end = rangeEnd ?? generatedAt;
    if (start == null) {
      return 'All recorded activity up to ${_pretty(end)}';
    }
    return '${_pretty(start)} - ${_pretty(end)}';
  }

  static String _pretty(DateTime date) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${names[date.month - 1]} ${date.year}';
  }

  String get netLabel => MoneyUtils.formatPaisa(netPaisa);
}
