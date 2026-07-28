import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme_controller.dart';
import 'firebase_options.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/main_navigation.dart';
import 'services/auth_service.dart';
import 'services/bill_reminder_service.dart';
import 'services/user_data_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
  }

  await UserDataService.initialize();
  await AppThemeController.load();
  await BillReminderService.initialize();
  await BillReminderService.rescheduleAll();

  runApp(const SmartExpenseApp());
}

class SmartExpenseApp extends StatelessWidget {
  const SmartExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (context, themeMode, child) {
        final seedColor = const Color(0xFF2A9D8F);
        final lightScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        );

        return MaterialApp(
          title: 'SmartExpense',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: lightScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: lightScheme.surface,
              foregroundColor: lightScheme.onSurface,
              iconTheme: IconThemeData(color: lightScheme.onSurface),
              elevation: 0,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: lightScheme.primary,
              foregroundColor: lightScheme.onPrimary,
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: lightScheme.primary,
              unselectedItemColor: Colors.grey[600],
              showUnselectedLabels: true,
              elevation: 8,
            ),
            cardTheme: CardThemeData(
              color: lightScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: lightScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
              labelStyle: TextStyle(color: lightScheme.onSurfaceVariant),
              hintStyle: TextStyle(color: lightScheme.onSurfaceVariant),
              prefixIconColor: lightScheme.onSurfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: lightScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: lightScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: lightScheme.primary, width: 1.5),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: lightScheme.primary,
                foregroundColor: lightScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.all(lightScheme.primary),
              trackColor: WidgetStateProperty.all(
                lightScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: lightScheme.surfaceContainerHighest,
              contentTextStyle: TextStyle(color: lightScheme.onSurface),
              actionTextColor: lightScheme.primary,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: darkScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: darkScheme.surface,
              foregroundColor: darkScheme.onSurface,
              iconTheme: IconThemeData(color: darkScheme.onSurface),
              elevation: 0,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: darkScheme.primary,
              foregroundColor: darkScheme.onPrimary,
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: darkScheme.surface,
              selectedItemColor: darkScheme.primary,
              unselectedItemColor: darkScheme.onSurfaceVariant,
              showUnselectedLabels: true,
              elevation: 8,
            ),
            cardTheme: CardThemeData(
              color: darkScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: darkScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
              labelStyle: TextStyle(color: darkScheme.onSurfaceVariant),
              hintStyle: TextStyle(color: darkScheme.onSurfaceVariant),
              prefixIconColor: darkScheme.onSurfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: darkScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: darkScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: darkScheme.primary, width: 1.5),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: darkScheme.primary,
                foregroundColor: darkScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.all(darkScheme.primary),
              trackColor: WidgetStateProperty.all(
                darkScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: darkScheme.surfaceContainerHighest,
              contentTextStyle: TextStyle(color: darkScheme.onSurface),
              actionTextColor: darkScheme.primary,
            ),
          ),
          themeMode: themeMode,
          home: StreamBuilder(
            stream: AuthService.authStateChanges,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              return snapshot.hasData
                  ? const MainNavigation()
                  : const LoginScreen();
            },
          ),
        );
      },
    );
  }
}
