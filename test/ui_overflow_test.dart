import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/components/app_widgets.dart';
import 'package:smartexpense/core/components/summary_item.dart';
import 'package:smartexpense/core/components/transaction_tile.dart';
import 'package:smartexpense/core/theme/app_theme.dart';

/// Renders [child] on a deliberately hostile screen: a narrow phone at the
/// largest text scale the app allows.
///
/// Overflow shows up as a RenderFlex exception, which [WidgetTester.takeException]
/// surfaces, so these tests fail loudly if a layout regresses.
Future<void> pumpHostile(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = const Size(320, 640),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: MediaQuery(
        // 1.3 is the ceiling main.dart clamps user text scaling to.
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  // A deliberately awful worst case: crore-scale money next to a long label.
  const hugeAmount = '- Rs. 12,34,56,789.99';
  const longTitle = 'Quarterly apartment maintenance and parking charges';

  group('TransactionTile', () {
    for (final brightness in Brightness.values) {
      testWidgets('survives a long title and a huge amount (${brightness.name})',
          (tester) async {
        await pumpHostile(
          tester,
          const TransactionTile(
            title: longTitle,
            category: 'Bills - Maintenance • 31/12/2026',
            amount: hugeAmount,
            isExpense: true,
            icon: Icons.receipt_long_rounded,
          ),
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('keeps the amount visible rather than clipping the row',
        (tester) async {
      await pumpHostile(
        tester,
        const TransactionTile(
          title: longTitle,
          category: 'Bills',
          amount: hugeAmount,
          isExpense: true,
          icon: Icons.receipt_long_rounded,
        ),
      );

      expect(find.text(hugeAmount), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('SummaryItem pair fits side by side at max text scale',
      (tester) async {
    await pumpHostile(
      tester,
      const ColoredBox(
        color: Color(0xFF2A9D8F),
        child: Row(
          children: [
            Expanded(
              child: SummaryItem(
                icon: Icons.arrow_downward_rounded,
                label: 'Income',
                amount: 'Rs. 12,34,56,789',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SummaryItem(
                icon: Icons.arrow_upward_rounded,
                label: 'Expenses',
                amount: 'Rs. 98,76,54,321',
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('ScreenHeader truncates instead of overflowing', (tester) async {
    await pumpHostile(
      tester,
      const ScreenHeader(
        title: 'An unreasonably long analytics screen title',
        subtitle: 'And a subtitle that also refuses to be short',
        icon: Icons.insights_rounded,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('SectionHeader fits a title plus a trailing action',
      (tester) async {
    await pumpHostile(
      tester,
      SectionHeader(
        title: 'Transaction History',
        trailing: TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.repeat_rounded, size: 16),
          label: const Text('Recurring'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('EmptyStateCard lays out with an action', (tester) async {
    await pumpHostile(
      tester,
      EmptyStateCard(
        icon: Icons.repeat_rounded,
        title: 'No recurring expenses',
        message:
            'Add rent, subscriptions, bills, or other repeating expenses and '
            'they will be recorded automatically.',
        actionLabel: 'Add first one',
        onAction: () {},
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('TransactionListSkeleton lays out', (tester) async {
    await pumpHostile(tester, const TransactionListSkeleton());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
