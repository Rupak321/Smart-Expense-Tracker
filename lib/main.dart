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
        return MaterialApp(
          title: 'Finance App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2A9D8F),
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2A9D8F),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121614),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          themeMode: themeMode,
          home: const MainNavigation(),
        );
      },
    );
  }
}
