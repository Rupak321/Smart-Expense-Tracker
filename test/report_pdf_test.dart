import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/models/financial_report.dart';
import 'package:smartexpense/services/financial_report_service.dart';
import 'package:smartexpense/services/report_pdf_builder.dart';

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

void main() {
  group('PDF text sanitising', () {
    // The built-in PDF fonts are Latin-1 only. Anything outside that draws as a
    // hollow box with a cross through it, which is exactly what the first
    // exported report showed in its footer.
    test('replaces dashes and bullets with ASCII', () {
      expect(ReportPdfBuilder.safeText('SmartExpense — All time'),
          'SmartExpense - All time');
      expect(ReportPdfBuilder.safeText('a – b'), 'a - b');
      expect(ReportPdfBuilder.safeText('• point'), '- point');
      expect(ReportPdfBuilder.safeText('a · b'), 'a - b');
    });

    test('flattens the smart quotes a language model produces', () {
      expect(
        ReportPdfBuilder.safeText('“your money” isn’t safe'),
        '"your money" isn\'t safe',
      );
    });

    test('expands ellipsis and rupee sign', () {
      expect(ReportPdfBuilder.safeText('wait…'), 'wait...');
      expect(ReportPdfBuilder.safeText('₹500'), 'Rs.500');
    });

    test('leaves ordinary text untouched', () {
      const plain = 'Food - Restaurant: Rs. 5,000 (9%)';
      expect(ReportPdfBuilder.safeText(plain), plain);
    });

    test('output is always representable in Latin-1', () {
      const nasty = 'Café — “quote” • ₹99 … 25°C ✓ 🎉 मोबाइल';
      final safe = ReportPdfBuilder.safeText(nasty);
      for (final rune in safe.runes) {
        expect(
          rune,
          lessThanOrEqualTo(0xFF),
          reason: 'U+${rune.toRadixString(16)} would render as a box',
        );
      }
    });

    test('does not silently blank a string it cannot represent', () {
      // Dropping every glyph would leave an empty cell in a table, which reads
      // as missing data rather than unsupported text.
      expect(ReportPdfBuilder.safeText('मोबाइल'), '(unsupported)');
      expect(ReportPdfBuilder.safeText(''), '');
    });

    test('keeps newlines so narrative paragraphs survive', () {
      expect(ReportPdfBuilder.safeText('one\ntwo'), 'one\ntwo');
    });
  });

  group('PDF document', () {
    FinancialReport reportFor(List<ExpenseModel> transactions) {
      return FinancialReportService.compute(
        transactions: transactions,
        period: ReportPeriod.allTime,
        now: DateTime(2026, 8, 15),
      );
    }

    test('builds a valid multi-page document with data', () async {
      final bytes = await ReportPdfBuilder.build(
        reportFor([
          for (var day = 1; day < 20; day++)
            tx(
              amount: 100.0 * day,
              isExpense: true,
              category: 'Cat$day',
              title: 'Expense $day',
              date: DateTime(2026, 7, day),
            ),
          tx(
            amount: 90000,
            isExpense: false,
            date: DateTime(2026, 7, 1),
            title: 'Salary',
          ),
        ]),
      );

      expect(bytes.length, greaterThan(2000));
      // %PDF- header.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('builds without throwing when the period is empty', () async {
      final bytes = await ReportPdfBuilder.build(reportFor(const []));

      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('survives hostile transaction titles', () async {
      final bytes = await ReportPdfBuilder.build(
        reportFor([
          tx(
            amount: 500,
            isExpense: true,
            date: DateTime(2026, 7, 2),
            title: 'Café — “deluxe” ₹ combo 🎉',
            category: 'Food • Dining',
          ),
        ]),
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders a narrative containing markdown and smart punctuation',
        () async {
      final base = reportFor([
        tx(amount: 500, isExpense: true, date: DateTime(2026, 7, 2)),
        tx(amount: 5000, isExpense: false, date: DateTime(2026, 7, 1)),
      ]);

      final bytes = await ReportPdfBuilder.build(
        base.copyWith(
          narrative: '## Overview\n'
              'You kept 90% — that’s strong.\n\n'
              '## What stands out\n'
              '- Food is the biggest line\n'
              '- Travel didn’t appear\n\n'
              '1. Cut Rs. 200\n'
              '2. Keep saving\n',
        ),
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });
  });
}
