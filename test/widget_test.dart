import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/theme/app_theme.dart';
import 'package:smartexpense/presentation/screens/main_navigation.dart';
import 'package:smartexpense/presentation/widgets/add_transaction_sheet.dart';

void main() {
  group('NavShellInsets', () {
    testWidgets('falls back to a plain gutter outside the tab shell',
        (tester) async {
      late double inset;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              inset = NavShellInsets.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(inset, AppTokens.gapLg);
    });

    testWidgets('publishes the shell inset to descendants', (tester) async {
      late double inset;
      await tester.pumpWidget(
        MaterialApp(
          home: NavShellInsets(
            contentBottom: 44,
            child: Builder(
              builder: (context) {
                inset = NavShellInsets.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(inset, 44);
    });
  });

  group('AddTransactionSheet', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(body: AddTransactionSheet()),
          ),
        ),
      );
    }

    testWidgets('lays out on a narrow screen at max text scale',
        (tester) async {
      await pumpSheet(tester);

      expect(find.text('Add Transaction'), findsOneWidget);
      expect(find.text('Save Transaction'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swapping to Income swaps the category list', (tester) async {
      await pumpSheet(tester);

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects an empty amount', (tester) async {
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Lunch');
      await tester.tap(find.text('Save Transaction'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter an amount'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
