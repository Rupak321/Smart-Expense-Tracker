import '../core/models/bill_reminder.dart';
import '../core/models/expense_model.dart';
import '../core/models/financial_insights.dart';
import '../core/models/recurring_expense_model.dart';
import '../core/utils/money_utils.dart';
import 'user_data_service.dart';
import 'user_settings_service.dart';

/// Turns raw transactions into the exact figures the assistant reasons about.
///
/// [compute] is a pure function so the maths can be tested without Firebase.
class FinancialInsightsService {
  const FinancialInsightsService._();

  /// How much a category has to grow month-over-month before it is worth
  /// mentioning.
  static const _categorySpikeRatio = 0.5;

  /// A spiking category only matters if it is a meaningful slice of spending.
  static const _categorySpikeMinShare = 0.15;

  /// Below this share of income kept, the assistant starts paying attention.
  static const _thinSavingsRate = 0.10;

  /// At or above this, the user is doing well and should hear it.
  static const _healthySavingsRate = 0.25;

  /// Loads everything the assistant needs and computes the picture.
  static Future<FinancialInsights> load({DateTime? now}) async {
    // Deliberately the *full* history, not a recent slice: these numbers are
    // presented to the user as their totals.
    final transactions = await UserDataService.getTransactionsOnce();

    List<RecurringExpenseModel> recurring;
    try {
      recurring = await UserDataService.getRecurringExpensesOnce();
    } catch (_) {
      recurring = const [];
    }

    List<BillReminder> bills;
    try {
      bills = await UserSettingsService.getBillRemindersOnce();
    } catch (_) {
      bills = const [];
    }

    return compute(
      transactions: transactions,
      recurring: recurring,
      bills: bills,
      now: now ?? DateTime.now(),
    );
  }

  static FinancialInsights compute({
    required List<ExpenseModel> transactions,
    required List<RecurringExpenseModel> recurring,
    required List<BillReminder> bills,
    required DateTime now,
  }) {
    var totalIncome = 0;
    var totalExpense = 0;
    DateTime? earliest;

    for (final transaction in transactions) {
      if (transaction.isExpense) {
        totalExpense += transaction.amountPaisa;
      } else {
        totalIncome += transaction.amountPaisa;
      }
      if (earliest == null || transaction.date.isBefore(earliest)) {
        earliest = transaction.date;
      }
    }

    final thisMonthStart = DateTime(now.year, now.month);
    final lastMonthStart = DateTime(now.year, now.month - 1);

    final thisMonth = _snapshotFor(transactions, thisMonthStart);
    final lastMonth = _snapshotFor(transactions, lastMonthStart);

    final thisMonthExpenses = transactions
        .where((t) => t.isExpense && _isInMonth(t.date, thisMonthStart))
        .toList();
    final lastMonthCategoryTotals = _categoryTotals(
      transactions.where(
        (t) => t.isExpense && _isInMonth(t.date, lastMonthStart),
      ),
    );

    final topCategories = _buildCategoryInsights(
      current: _categoryTotals(thisMonthExpenses),
      previous: lastMonthCategoryTotals,
      totalThisMonth: thisMonth.expensePaisa,
    );

    final biggest = List<ExpenseModel>.from(thisMonthExpenses)
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final last30 = transactions
        .where((t) => t.isExpense && t.date.isAfter(thirtyDaysAgo))
        .fold(0, (sum, t) => sum + t.amountPaisa);

    final committed = _monthlyCommitment(recurring);
    final upcoming = _upcomingCommitments(recurring, bills, now);

    final concerns = <String>[];
    final wins = <String>[];
    final stance = _decideStance(
      thisMonth: thisMonth,
      lastMonth: lastMonth,
      balancePaisa: totalIncome - totalExpense,
      categories: topCategories,
      concerns: concerns,
      wins: wins,
    );

    return FinancialInsights(
      totalIncomePaisa: totalIncome,
      totalExpensePaisa: totalExpense,
      transactionCount: transactions.length,
      earliestDate: earliest,
      generatedAt: now,
      thisMonth: thisMonth,
      lastMonth: lastMonth,
      topCategories: topCategories,
      biggestExpensesThisMonth: biggest.take(5).toList(),
      last30DaysExpensePaisa: last30,
      committedMonthlyPaisa: committed,
      upcoming: upcoming,
      stance: stance,
      concerns: concerns,
      wins: wins,
    );
  }

  static bool _isInMonth(DateTime date, DateTime monthStart) {
    return date.year == monthStart.year && date.month == monthStart.month;
  }

  static MonthlySnapshot _snapshotFor(
    List<ExpenseModel> transactions,
    DateTime monthStart,
  ) {
    var income = 0;
    var expense = 0;
    var count = 0;

    for (final transaction in transactions) {
      if (!_isInMonth(transaction.date, monthStart)) continue;
      count++;
      if (transaction.isExpense) {
        expense += transaction.amountPaisa;
      } else {
        income += transaction.amountPaisa;
      }
    }

    return MonthlySnapshot(
      month: monthStart,
      incomePaisa: income,
      expensePaisa: expense,
      transactionCount: count,
    );
  }

  static Map<String, int> _categoryTotals(Iterable<ExpenseModel> expenses) {
    final totals = <String, int>{};
    for (final expense in expenses) {
      totals.update(
        expense.category,
        (value) => value + expense.amountPaisa,
        ifAbsent: () => expense.amountPaisa,
      );
    }
    return totals;
  }

  static List<CategoryInsight> _buildCategoryInsights({
    required Map<String, int> current,
    required Map<String, int> previous,
    required int totalThisMonth,
  }) {
    final insights = current.entries.map((entry) {
      return CategoryInsight(
        label: entry.key,
        paisa: entry.value,
        previousPaisa: previous[entry.key] ?? 0,
        share: totalThisMonth <= 0 ? 0 : entry.value / totalThisMonth,
      );
    }).toList();

    insights.sort((first, second) => second.paisa.compareTo(first.paisa));
    return insights;
  }

  /// Normalises every active recurring expense to a monthly figure so the
  /// assistant knows what is already spoken for before advising on spending.
  static int _monthlyCommitment(List<RecurringExpenseModel> recurring) {
    var total = 0;
    for (final expense in recurring) {
      if (expense.status != RecurringStatus.active) continue;
      final interval = expense.interval <= 0 ? 1 : expense.interval;
      final paisa = MoneyUtils.amountToPaisa(expense.amount);
      final monthly = switch (expense.frequency) {
        RecurringFrequency.daily => paisa * 30 / interval,
        RecurringFrequency.weekly => paisa * 52 / 12 / interval,
        RecurringFrequency.monthly => paisa / interval,
        RecurringFrequency.yearly => paisa / 12 / interval,
      };
      total += monthly.round();
    }
    return total;
  }

  static List<UpcomingCommitment> _upcomingCommitments(
    List<RecurringExpenseModel> recurring,
    List<BillReminder> bills,
    DateTime now,
  ) {
    final horizon = now.add(const Duration(days: 14));
    final items = <UpcomingCommitment>[];

    for (final expense in recurring) {
      if (expense.status != RecurringStatus.active) continue;
      if (expense.nextDueDate.isAfter(horizon)) continue;
      items.add(
        UpcomingCommitment(
          title: expense.title,
          paisa: MoneyUtils.amountToPaisa(expense.amount),
          dueDate: expense.nextDueDate,
          source: 'recurring',
        ),
      );
    }

    for (final bill in bills) {
      if (!bill.enabled) continue;
      if (bill.dueDate.isAfter(horizon)) continue;
      items.add(
        UpcomingCommitment(
          title: bill.title,
          paisa: MoneyUtils.amountToPaisa(bill.amount),
          dueDate: bill.dueDate,
          source: 'bill',
        ),
      );
    }

    items.sort((first, second) => first.dueDate.compareTo(second.dueDate));
    return items;
  }

  /// Picks the tone from the numbers, and records why.
  ///
  /// The [concerns] and [wins] it fills are handed to the model verbatim so its
  /// advice points at real figures instead of generic budgeting platitudes.
  static CoachStance _decideStance({
    required MonthlySnapshot thisMonth,
    required MonthlySnapshot lastMonth,
    required int balancePaisa,
    required List<CategoryInsight> categories,
    required List<String> concerns,
    required List<String> wins,
  }) {
    if (!thisMonth.hasActivity && !lastMonth.hasActivity) {
      return CoachStance.calm;
    }

    final savingsRate = thisMonth.savingsRate;

    if (balancePaisa < 0) {
      concerns.add(
        'Recorded balance is negative at '
        '${MoneyUtils.formatPaisa(balancePaisa)} — total spending has passed '
        'total income.',
      );
    }

    if (thisMonth.isOverspending && thisMonth.incomePaisa > 0) {
      concerns.add(
        'This month spending is '
        '${MoneyUtils.formatPaisa(thisMonth.expensePaisa)} against income of '
        '${MoneyUtils.formatPaisa(thisMonth.incomePaisa)} — over by '
        '${MoneyUtils.formatPaisa(thisMonth.netPaisa.abs())}.',
      );
    }

    for (final category in categories.take(4)) {
      final ratio = category.changeRatio;
      if (ratio != null &&
          ratio >= _categorySpikeRatio &&
          category.share >= _categorySpikeMinShare) {
        concerns.add(
          '${category.label} is up ${(ratio * 100).round()}% vs last month '
          '(${MoneyUtils.formatPaisa(category.previousPaisa)} to '
          '${MoneyUtils.formatPaisa(category.paisa)}).',
        );
      }
    }

    if (savingsRate != null) {
      if (savingsRate >= _healthySavingsRate) {
        wins.add(
          'Kept ${(savingsRate * 100).round()}% of income this month '
          '(${MoneyUtils.formatPaisa(thisMonth.netPaisa)}).',
        );
      } else if (savingsRate > 0 && savingsRate < _thinSavingsRate) {
        concerns.add(
          'Only ${(savingsRate * 100).round()}% of income kept this month — '
          'thin cushion if something unexpected lands.',
        );
      }
    }

    // Only a real win once there is something recorded to compare. Early in a
    // month an empty ledger looks like a huge drop in spending, and
    // congratulating someone for not having logged anything yet is worse than
    // saying nothing.
    if (thisMonth.hasActivity &&
        lastMonth.expensePaisa > 0 &&
        thisMonth.expensePaisa < lastMonth.expensePaisa) {
      final saved = lastMonth.expensePaisa - thisMonth.expensePaisa;
      wins.add(
        'Spending is down ${MoneyUtils.formatPaisa(saved)} vs last month.',
      );
    }

    // Strict is reserved for money actually going backwards, so it keeps its
    // weight when it does fire.
    final spendingMoreThanEarning = savingsRate != null && savingsRate < 0;
    if (spendingMoreThanEarning || balancePaisa < 0) {
      return CoachStance.strict;
    }

    if (concerns.isNotEmpty ||
        (savingsRate != null && savingsRate < _thinSavingsRate)) {
      return CoachStance.watchful;
    }

    if (savingsRate != null && savingsRate >= _healthySavingsRate) {
      return CoachStance.encouraging;
    }

    return CoachStance.calm;
  }
}
