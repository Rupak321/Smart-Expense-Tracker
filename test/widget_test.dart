import 'package:flutter_test/flutter_test.dart';

import 'package:smartexpense/main.dart';

void main() {
  testWidgets('shows finance app home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartExpenseApp());

    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.text('Transactions History'), findsOneWidget);
  });
}
