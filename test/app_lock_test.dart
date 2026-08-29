import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/theme/app_theme.dart';
import 'package:smartexpense/presentation/screens/lock_screen.dart';
import 'package:smartexpense/services/app_lock_service.dart';

void main() {
  tearDown(() => AppLockService.resetForTest());

  group('when the gate asks for a lock', () {
    test('a disabled lock never asks', () {
      AppLockService.resetForTest(enabled: false);
      expect(AppLockService.needsUnlock, isFalse);
    });

    test('an enabled lock asks until it is passed', () {
      AppLockService.resetForTest(enabled: true);
      expect(AppLockService.needsUnlock, isTrue);

      AppLockService.resetForTest(enabled: true, unlocked: true);
      expect(AppLockService.needsUnlock, isFalse);
    });

    test('backgrounding re-arms an enabled lock', () {
      AppLockService.resetForTest(enabled: true, unlocked: true);
      AppLockService.lock();
      expect(AppLockService.needsUnlock, isTrue);
    });

    test('backgrounding does nothing when the lock is off', () {
      AppLockService.resetForTest(enabled: false, unlocked: true);
      AppLockService.lock();
      expect(AppLockService.needsUnlock, isFalse);
    });
  });

  group('the lock screen', () {
    testWidgets('explains itself and offers a retry', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: LockScreen(onUnlocked: () {}),
        ),
      );
      // Settle only the first frame: the screen prompts immediately, and there
      // is no platform to answer it in a test.
      await tester.pump();

      expect(find.text('SmartExpense is locked'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });
  });
}
