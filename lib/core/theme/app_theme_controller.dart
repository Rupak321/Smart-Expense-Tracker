import 'package:flutter/material.dart';

import '../../services/user_settings_service.dart';

class AppThemeController {
  const AppThemeController._();

  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.system,
  );

  static Future<void> load() async {
    final mode = await UserSettingsService.loadThemeMode();
    themeMode.value = mode;
  }

  static bool get isDarkMode => themeMode.value == ThemeMode.dark;

  static Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode.value == mode) {
      return;
    }
    themeMode.value = mode;
    await UserSettingsService.saveThemeMode(mode);
  }

  static Future<void> setDarkMode(bool enabled) {
    return setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  /// Human readable label for the current mode, used in Settings.
  static String labelFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Match device',
    };
  }

  static IconData iconFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
  }
}
