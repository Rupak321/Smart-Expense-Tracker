import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/budget.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/services/data_export_service.dart';

ExpenseModel tx(
  String title, {
  String category = 'Other',
  double amount = 100,
  bool isExpense = true,
  bool isWindfall = false,
  DateTime? date,
}) {
  return ExpenseModel(
    id: title,
    title: title,
    amount: amount,
    category: category,
    date: date ?? DateTime(2026, 8, 20),
    isExpense: isExpense,
    isWindfall: isWindfall,
  );
}

void main() {
  group('CSV escaping', () {
    test('plain text is left alone', () {
      expect(DataExportService.escapeCsvField('Lunch'), 'Lunch');
    });

    test('a comma forces quoting, or it would shift every later column', () {
      expect(
        DataExportService.escapeCsvField('Rice, dal and milk'),
        '"Rice, dal and milk"',
      );
    });

    test('a quote is doubled inside quotes', () {
      expect(
        DataExportService.escapeCsvField('The "good" cafe'),
        '"The ""good"" cafe"',
      );
    });

    test('a newline inside a field is quoted, not emitted raw', () {
      final escaped = DataExportService.escapeCsvField('line one\nline two');
      expect(escaped.startsWith('"'), isTrue);
      expect(escaped.endsWith('"'), isTrue);
    });
  });

  group('transaction rows', () {
    test('the header names every column that follows', () {
      final csv = DataExportService.buildTransactionCsv([tx('Lunch')]);
      final header = csv.split('\n').first.split(',');
      final row = csv.split('\n')[1].split(',');

      expect(header.length, row.length);
      expect(header.first, 'Date');
    });

    test('amounts are plain numbers a spreadsheet can add up', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Big', amount: 8500000),
      ]);

      // No symbol and no thousands separators.
      expect(csv, contains('8500000.00'));
      expect(csv, isNot(contains('Rs.')));
      expect(csv, isNot(contains('8,500,000')));
    });

    test('paisa survive the export', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Tea', amount: 12.5),
      ]);
      expect(csv, contains('12.50'));
    });

    test('direction is spelled out rather than left as a boolean', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Salary', isExpense: false),
        tx('Lunch'),
      ]);

      expect(csv, contains('Income'));
      expect(csv, contains('Expense'));
    });

    test('rows come out newest first', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Older', date: DateTime(2026, 5, 1)),
        tx('Newer', date: DateTime(2026, 8, 1)),
      ]);
      final lines = csv.trim().split('\n');

      expect(lines[1], contains('Newer'));
      expect(lines[2], contains('Older'));
    });

    test('dates are ISO so they sort and parse anywhere', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Lunch', date: DateTime(2026, 8, 5)),
      ]);
      expect(csv, contains('2026-08-05'));
    });

    test('a title full of separators still produces one row per record', () {
      final csv = DataExportService.buildTransactionCsv([
        tx('Rice, dal, "extra"', category: 'Food, general'),
        tx('Plain'),
      ]);

      // Header plus exactly two records.
      expect(csv.trim().split('\n'), hasLength(3));
    });

    test('an empty ledger still emits the header', () {
      final csv = DataExportService.buildTransactionCsv([]);
      expect(csv.trim().split('\n'), hasLength(1));
    });
  });

  group('budgets', () {
    test('an overall budget exports under a readable label', () {
      final csv = DataExportService.buildBudgetCsv([
        Budget(
          id: 'a',
          category: null,
          limitPaisa: 2000000,
          createdAt: DateTime(2026, 8, 1),
        ),
      ]);

      expect(csv, contains('Everything'));
      expect(csv, contains('20000.00'));
    });
  });

  group('the summary line', () {
    test('says what the file holds', () {
      final summary = DataExportService.buildSummary([
        tx('Salary', amount: 60000, isExpense: false, date: DateTime(2026, 8, 1)),
        tx('Lunch', amount: 450, date: DateTime(2026, 8, 20)),
      ]);

      expect(summary, contains('2 transactions'));
      expect(summary, contains('2026-08-01'));
      expect(summary, contains('2026-08-20'));
    });

    test('an empty export says so rather than showing zeroes', () {
      expect(DataExportService.buildSummary([]), 'No transactions recorded.');
    });
  });

  test('the file name is stamped and ends in .csv', () {
    final name = DataExportService.fileNameFor(DateTime(2026, 8, 5, 9, 7));
    expect(name, 'smartexpense_20260805_0907.csv');
  });
}
