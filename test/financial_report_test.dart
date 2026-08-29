import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/models/financial_report.dart';
import 'package:smartexpense/services/financial_report_service.dart';

final now = DateTime(2026, 8, 15, 12);

ExpenseModel tx({
  required double amount,
  required bool isExpense,
  required DateTime date,
  String category = 'Other',
  String title = 'Item',
}) {
  return ExpenseModel(
    id: '$title-$amount-$date',
    title: title,
    amount: amount,
    category: category,
    date: date,
    isExpense: isExpense,
  );
}

FinancialReport build(List<ExpenseModel> transactions, ReportPeriod period) {
  return FinancialReportService.compute(
    transactions: transactions,
    period: period,
    now: now,
  );
}

void main() {
  group('period windows actually filter', () {
    // The original bug: every option produced an identical all-time report
    // because the chosen period was never applied to the query.
    final ledger = [
      tx(amount: 100, isExpense: true, date: DateTime(2026, 8, 14)), // 1d ago
      tx(amount: 200, isExpense: true, date: DateTime(2026, 8, 2)), // this mth
      tx(amount: 400, isExpense: true, date: DateTime(2026, 7, 20)), // last mth
      tx(amount: 800, isExpense: true, date: DateTime(2026, 5, 5)), // older
      tx(amount: 1600, isExpense: true, date: DateTime(2025, 11, 5)), // last yr
    ];

    test('last 7 days keeps only the last week', () {
      final report = build(ledger, ReportPeriod.last7Days);
      expect(report.expenseCount, 1);
      expect(report.expensePaisa, 10000);
    });

    test('month to date keeps only this calendar month', () {
      final report = build(ledger, ReportPeriod.monthToDate);
      expect(report.expenseCount, 2);
      expect(report.expensePaisa, 30000);
    });

    test('last month keeps only the previous calendar month', () {
      final report = build(ledger, ReportPeriod.lastMonth);
      expect(report.expenseCount, 1);
      expect(report.expensePaisa, 40000);
    });

    test('last 3 months spans June to August', () {
      final report = build(ledger, ReportPeriod.last3Months);
      expect(report.expenseCount, 3);
      expect(report.expensePaisa, 70000);
    });

    test('this year excludes last year', () {
      final report = build(ledger, ReportPeriod.thisYear);
      expect(report.expenseCount, 4);
      expect(report.expensePaisa, 150000);
    });

    test('all time keeps everything', () {
      final report = build(ledger, ReportPeriod.allTime);
      expect(report.expenseCount, 5);
      expect(report.expensePaisa, 310000);
    });

    test('the periods genuinely differ from one another', () {
      final totals = ReportPeriod.values
          .map((period) => build(ledger, period).expensePaisa)
          .toSet();
      // If filtering were broken every period would collapse to one value.
      expect(totals.length, greaterThan(4));
    });
  });

  group('totals and rates', () {
    test('separates income from expenditure', () {
      final report = build([
        tx(amount: 1000, isExpense: false, date: DateTime(2026, 8, 3)),
        tx(amount: 250, isExpense: true, date: DateTime(2026, 8, 4)),
      ], ReportPeriod.monthToDate);

      expect(report.incomePaisa, 100000);
      expect(report.expensePaisa, 25000);
      expect(report.netPaisa, 75000);
      expect(report.savingsRate, closeTo(0.75, 0.0001));
    });

    test('savings rate is null with no income', () {
      final report = build([
        tx(amount: 250, isExpense: true, date: DateTime(2026, 8, 4)),
      ], ReportPeriod.monthToDate);

      expect(report.savingsRate, isNull);
    });

    test('empty period reports no data rather than throwing', () {
      final report = build(const [], ReportPeriod.last7Days);

      expect(report.hasData, isFalse);
      expect(report.expensePaisa, 0);
      expect(report.observations, isEmpty);
      expect(report.rangeLabel, isNotEmpty);
    });
  });

  group('previous period comparison', () {
    test('compares against the equally long window before it', () {
      final report = build([
        // Current 7 days.
        tx(amount: 300, isExpense: true, date: DateTime(2026, 8, 12)),
        // The 7 days before that.
        tx(amount: 200, isExpense: true, date: DateTime(2026, 8, 5)),
      ], ReportPeriod.last7Days);

      expect(report.expensePaisa, 30000);
      expect(report.previousExpensePaisa, 20000);
      expect(report.expenseChangeRatio, closeTo(0.5, 0.0001));
    });

    test('all time has no previous window to compare with', () {
      final report = build([
        tx(amount: 300, isExpense: true, date: DateTime(2026, 8, 12)),
      ], ReportPeriod.allTime);

      expect(report.previousExpensePaisa, isNull);
      expect(report.expenseChangeRatio, isNull);
    });
  });

  group('breakdowns', () {
    test('categories rank by size and carry share and count', () {
      final report = build([
        tx(
          amount: 600,
          isExpense: true,
          category: 'Food',
          date: DateTime(2026, 8, 2),
        ),
        tx(
          amount: 200,
          isExpense: true,
          category: 'Food',
          date: DateTime(2026, 8, 3),
        ),
        tx(
          amount: 200,
          isExpense: true,
          category: 'Travel',
          date: DateTime(2026, 8, 4),
        ),
      ], ReportPeriod.monthToDate);

      expect(report.categories.first.label, 'Food');
      expect(report.categories.first.paisa, 80000);
      expect(report.categories.first.transactionCount, 2);
      expect(report.categories.first.share, closeTo(0.8, 0.0001));
      expect(report.categories.last.label, 'Travel');
    });

    test('largest expenses are ranked by amount, not by date', () {
      final report = build([
        tx(amount: 50, isExpense: true, date: DateTime(2026, 8, 14)),
        tx(amount: 900, isExpense: true, date: DateTime(2026, 8, 2)),
        tx(amount: 300, isExpense: true, date: DateTime(2026, 8, 9)),
      ], ReportPeriod.monthToDate);

      expect(
        report.topExpenses.map((e) => e.amount).toList(),
        [900, 300, 50],
      );
      expect(report.largestExpense?.amount, 900);
    });

    test('months are grouped and ordered chronologically', () {
      final report = build([
        tx(amount: 100, isExpense: true, date: DateTime(2026, 8, 2)),
        tx(amount: 200, isExpense: true, date: DateTime(2026, 7, 2)),
        tx(amount: 300, isExpense: false, date: DateTime(2026, 7, 3)),
      ], ReportPeriod.last3Months);

      expect(report.months.length, 2);
      expect(report.months.first.month.month, 7);
      expect(report.months.first.expensePaisa, 20000);
      expect(report.months.first.incomePaisa, 30000);
      expect(report.months.last.month.month, 8);
    });
  });

  group('observations', () {
    test('flag overspending explicitly', () {
      final report = build([
        tx(amount: 100, isExpense: false, date: DateTime(2026, 8, 2)),
        tx(amount: 500, isExpense: true, date: DateTime(2026, 8, 3)),
      ], ReportPeriod.monthToDate);

      expect(
        report.observations.any((o) => o.contains('exceeded income')),
        isTrue,
      );
    });

    test('flag a dominant category', () {
      final report = build([
        tx(
          amount: 900,
          isExpense: true,
          category: 'Food',
          date: DateTime(2026, 8, 2),
        ),
        tx(
          amount: 100,
          isExpense: true,
          category: 'Travel',
          date: DateTime(2026, 8, 3),
        ),
      ], ReportPeriod.monthToDate);

      expect(report.observations.any((o) => o.contains('Food')), isTrue);
    });

    test('are generated without any network or API key', () {
      final report = build([
        tx(amount: 1000, isExpense: false, date: DateTime(2026, 8, 2)),
        tx(amount: 200, isExpense: true, date: DateTime(2026, 8, 3)),
      ], ReportPeriod.monthToDate);

      expect(report.narrative, isNull);
      expect(report.observations, isNotEmpty);
    });
  });

  group('averages', () {
    test('per-day average divides by the window length', () {
      final report = build([
        tx(amount: 700, isExpense: true, date: DateTime(2026, 8, 12)),
      ], ReportPeriod.last7Days);

      expect(report.dayCount, 7);
      expect(report.averageDailyExpensePaisa, 10000);
    });

    test('per-transaction average divides by expense count', () {
      final report = build([
        tx(amount: 300, isExpense: true, date: DateTime(2026, 8, 12)),
        tx(amount: 100, isExpense: true, date: DateTime(2026, 8, 13)),
      ], ReportPeriod.last7Days);

      expect(report.averageExpensePerTransactionPaisa, 20000);
    });
  });
}
