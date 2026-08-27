import 'package:flutter/material.dart';

import '../../models/user_settings.dart' as settings;
import '../data/user_settings_service.dart';
import 'theme_service.dart';

/// Applies appearance changes to both the live app and account-scoped settings.
class ThemePreferencesController {
  ThemePreferencesController._();

  static final ThemePreferencesController _instance =
      ThemePreferencesController._();
  factory ThemePreferencesController() => _instance;

  Future<void> setTheme(AppTheme theme) async {
    await ThemeService().setTheme(theme);
    await UserSettingsService().updateThemeVariant(theme);
  }

  Future<void> setThemeMode(settings.AppThemeMode mode) async {
    final materialMode = switch (mode) {
      settings.AppThemeMode.light => ThemeMode.light,
      settings.AppThemeMode.dark => ThemeMode.dark,
      settings.AppThemeMode.system => ThemeMode.system,
    };
    await ThemeService().setThemeMode(materialMode);
    await UserSettingsService().updateThemeMode(mode);
  }
}
