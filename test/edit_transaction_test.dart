import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_category.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/theme/app_theme.dart';
import 'package:smartexpense/core/utils/money_utils.dart';
import 'package:smartexpense/presentation/widgets/add_transaction_sheet.dart';

void main() {
  final categories = ExpenseCategory.defaults(DateTime(2026, 8, 1));

  Future<void> pump(WidgetTester tester, {ExpenseModel? existing}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AddTransactionSheet(
            categoriesOverride: categories,
            existing: existing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final lunch = ExpenseModel(
    id: 'abc',
    title: 'Lunch at Thakali',
    amount: 450,
    category: 'Food & Dining',
    date: DateTime(2026, 8, 20),
    isExpense: true,
  );

  group('adding', () {
    testWidgets('opens empty and offers to save', (tester) async {
      await pump(tester);

      expect(find.text('Add Transaction'), findsOneWidget);
      expect(find.text('Save Transaction'), findsOneWidget);
      expect(find.text('Edit Transaction'), findsNothing);
    });

    testWidgets('defaults the date to today', (tester) async {
      await pump(tester);

      expect(find.text('Today'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('prefills every field from the transaction', (tester) async {
      await pump(tester, existing: lunch);

      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Lunch at Thakali'), findsOneWidget);
      expect(find.text('450'), findsOneWidget);
      // The stored date, not today.
      expect(find.text('20 Aug'), findsOneWidget);
    });

    testWidgets('an amount with paisa round-trips into the field',
        (tester) async {
      await pump(
        tester,
        existing: ExpenseModel(
          id: 'x',
          title: 'Tea',
          amount: 12.5,
          category: 'Food & Dining',
          date: DateTime(2026, 8, 20),
          isExpense: true,
        ),
      );

      expect(find.text('12.50'), findsOneWidget);
    });

    testWidgets('income keeps its direction and one-off toggle',
        (tester) async {
      await pump(
        tester,
        existing: ExpenseModel(
          id: 'y',
          title: 'Sale of land',
          amount: 8500000,
          category: 'Salary',
          date: DateTime(2026, 8, 9),
          isExpense: false,
          isWindfall: true,
        ),
      );

      // The one-off control only renders for income, so finding it proves the
      // direction survived the round trip.
      expect(find.text('One-off income'), findsOneWidget);
    });
  });

  group('the amount helper the prefill relies on', () {
    test('drops trailing paisa when there are none', () {
      expect(MoneyUtils.editableAmount(450), '450');
    });

    test('keeps two places when there are paisa', () {
      expect(MoneyUtils.editableAmount(12.5), '12.50');
      expect(MoneyUtils.editableAmount(0.05), '0.05');
    });

    test('parses back to the same value it came from', () {
      for (final amount in [450.0, 12.5, 0.05, 8500000.0, 99.99]) {
        expect(
          MoneyUtils.parseToPaisa(MoneyUtils.editableAmount(amount)),
          MoneyUtils.amountToPaisa(amount),
          reason: '$amount must survive the round trip',
        );
      }
    });
  });
}
