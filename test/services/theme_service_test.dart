import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:flutter/material.dart';

/// [ThemeService]: what it restores at launch, and what it hands to Material.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ThemeService();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  // Migration idempotency / robustness for initialize(). The theme used to be
  // persisted as an enum *index*; it is now a stable enum *name*. initialize()
  // migrates the old integer to the new name key, drops the old key, and —
  // crucially — must be a no-op on every subsequent launch and must never throw
  // on an out-of-range or unknown stored value: run-once, run-again-safe, and
  // junk-tolerant.
  test('old integer index migrates to the new name key and drops the old key',
      () async {
    await prefsWith({StorageKeys.selectedTheme: 1}); // 1 == draculaDark
    await service.initialize();

    expect(service.currentTheme, AppTheme.draculaDark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.selectedThemeName),
        AppTheme.draculaDark.name);
    expect(prefs.getInt(StorageKeys.selectedTheme), isNull,
        reason: 'old key must be removed after migrating');
  });

  test('re-running the migration is a no-op (idempotent across launches)',
      () async {
    await prefsWith({StorageKeys.selectedTheme: 5}); // 5 == nordDark
    await service.initialize();
    final afterFirst = service.currentTheme;
    expect(afterFirst, AppTheme.nordDark);

    // Simulate a second app launch against the now-migrated store.
    await service.initialize();
    expect(service.currentTheme, afterFirst);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(StorageKeys.selectedTheme), isNull);
    expect(prefs.getString(StorageKeys.selectedThemeName),
        AppTheme.nordDark.name);
  });

  test('an out-of-range or unmapped old index falls back without throwing',
      () async {
    for (final bad in [-1, 13, 999, 4]) {
      await prefsWith({StorageKeys.selectedTheme: bad});
      await service.initialize();
      expect(service.currentTheme, AppTheme.githubDark,
          reason: 'unmapped index $bad should fall back to the default');
    }
  });

  test('the new name key wins and the stale integer is ignored', () async {
    await prefsWith({
      StorageKeys.selectedThemeName: AppTheme.nordDark.name,
      StorageKeys.selectedTheme: 1, // stale; must not override the name
    });
    await service.initialize();
    expect(service.currentTheme, AppTheme.nordDark);
  });

  test('an unknown stored theme name falls back to the default', () async {
    await prefsWith({StorageKeys.selectedThemeName: 'theme_that_was_removed'});
    await service.initialize();
    expect(service.currentTheme, AppTheme.githubDark);
  });

  test('a clean install (no theme keys) keeps the default', () async {
    await prefsWith({});
    await service.initialize();
    expect(service.currentTheme, AppTheme.githubDark);
  });

  group('bundled Inter', () {
    // Guards the swap away from google_fonts: if someone reintroduces a
    // runtime-fetched family (or a Roboto default slips back in), the text
    // theme stops reading "Inter" and this fails.
    test('every text style uses the bundled Inter family', () {
      final theme = ThemeService().getLightThemeData(AppTheme.githubDark);
      final t = theme.textTheme;

      final styles = <TextStyle?>[
        t.displayLarge, t.displayMedium, t.displaySmall,
        t.headlineLarge, t.headlineMedium, t.headlineSmall,
        t.titleLarge, t.titleMedium, t.titleSmall,
        t.bodyLarge, t.bodyMedium, t.bodySmall,
        t.labelLarge, t.labelMedium, t.labelSmall,
      ];

      for (final style in styles) {
        expect(style?.fontFamily, 'Inter');
      }
    });

    test('the explicit dialog title style is Inter too', () {
      // The one style built as a bare TextStyle rather than via the text theme
      // — it has to name the family itself.
      final theme = ThemeService().getDarkThemeData(AppTheme.githubDark);
      expect(theme.dialogTheme.titleTextStyle?.fontFamily, 'Inter');
    });

    test('weights survive the variable-font mapping', () {
      // The variable file carries the weight axis; a heading must stay heavier
      // than body text rather than collapsing to one rendered weight.
      final t = ThemeService().getLightThemeData(AppTheme.githubDark).textTheme;
      expect(
        t.headlineMedium!.fontWeight!.value,
        greaterThanOrEqualTo(t.bodyMedium!.fontWeight!.value),
      );
    });
  });
}
