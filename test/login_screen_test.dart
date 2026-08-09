import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/theme/app_theme.dart';
import 'package:smartexpense/presentation/screens/login_screen.dart';

void main() {
  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    );
  }

  testWidgets('shows the sign-in form by default', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // 'Sign in' appears twice: the mode toggle and the submit button.
    expect(find.text('Sign in'), findsNWidgets(2));
    // The name field belongs to the register mode only.
    expect(find.text('Name'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('switching to Create reveals the name field', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('password visibility can be toggled', (tester) async {
    await pumpLogin(tester);

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });
}
