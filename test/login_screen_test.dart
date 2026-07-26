import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/presentation/screens/login_screen.dart';

void main() {
  testWidgets('shows the authentication form and mode toggle', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}
