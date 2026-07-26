import 'package:flutter/material.dart';

import '../../services/user_settings_service.dart';

class AppThemeController {
  const AppThemeController._();

  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.light,
  );

  static Future<void> load() async {
    final mode = await UserSettingsService.loadThemeMode();
    themeMode.value = mode;
  }

  static bool get isDarkMode => themeMode.value == ThemeMode.dark;

  static Future<void> setDarkMode(bool enabled) async {
    final mode = enabled ? ThemeMode.dark : ThemeMode.light;
    themeMode.value = mode;
    await UserSettingsService.saveThemeMode(mode);
  }
}
