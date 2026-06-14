import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_android/path_provider_android.dart';

import 'core/models/expense_model.dart';
import 'core/models/user_profile_model.dart';
import 'core/theme/app_theme_controller.dart';
import 'presentation/screens/main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initHive();
  runApp(const MyApp());
}

Future<void> _initHive() async {
  final androidPathProvider = PathProviderAndroid();
  final storagePath = await androidPathProvider.getApplicationSupportPath();
  final hiveDirectory = Directory(storagePath ?? '.hive');
  await hiveDirectory.create(recursive: true);

  Hive.init(hiveDirectory.path);

  if (!Hive.isAdapterRegistered(ExpenseModelAdapter().typeId)) {
    Hive.registerAdapter(ExpenseModelAdapter());
  }
  if (!Hive.isAdapterRegistered(UserProfileModelAdapter().typeId)) {
    Hive.registerAdapter(UserProfileModelAdapter());
  }

  if (!Hive.isBoxOpen('transactions')) {
    await Hive.openBox<ExpenseModel>('transactions');
  }
  if (!Hive.isBoxOpen('user_profile')) {
    await Hive.openBox<UserProfileModel>('user_profile');
  }
  // Open settings box used for persisting app settings (theme, etc.)
  if (!Hive.isBoxOpen('settings')) {
    await Hive.openBox('settings');
  }

  // Load stored theme preference (if any)
  await AppThemeController.load();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          title: 'Finance App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: lightScheme.background,
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
              // Preserve previous light-mode look (explicit white background)
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
                borderSide: BorderSide(
                  color: lightScheme.primary,
                  width: 1.5,
                ),
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
              thumbColor: MaterialStateProperty.all(lightScheme.primary),
              trackColor: MaterialStateProperty.all(
                lightScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: lightScheme.surfaceVariant,
              contentTextStyle: TextStyle(color: lightScheme.onSurface),
              actionTextColor: lightScheme.primary,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: darkScheme.background,
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
              // Dark mode uses theme surface to keep proper contrast
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
                borderSide: BorderSide(
                  color: darkScheme.primary,
                  width: 1.5,
                ),
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
              thumbColor: MaterialStateProperty.all(darkScheme.primary),
              trackColor: MaterialStateProperty.all(
                darkScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: darkScheme.surfaceVariant,
              contentTextStyle: TextStyle(color: darkScheme.onSurface),
              actionTextColor: darkScheme.primary,
            ),
          ),
          themeMode: themeMode,
          home: const MainNavigation(),
        );
      },
    );
  }
}
