import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class AppThemeController {
  const AppThemeController._();

  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.light,
  );

  static const _boxName = 'settings';
  static const _key = 'theme_mode';

  /// Load persisted theme from Hive settings box. Call after Hive.init().
  static Future<void> load() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }

    final box = Hive.box(_boxName);
    final stored = box.get(_key) as String?;
    if (stored == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else if (stored == 'system') {
      themeMode.value = ThemeMode.system;
    } else {
      themeMode.value = ThemeMode.light;
    }
  }

  static bool get isDarkMode => themeMode.value == ThemeMode.dark;

  static void setDarkMode(bool enabled) {
    themeMode.value = enabled ? ThemeMode.dark : ThemeMode.light;

    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box(_boxName);
      box.put(_key, enabled ? 'dark' : 'light');
    }
  }
}
