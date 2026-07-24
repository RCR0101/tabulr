import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';

/// Migration idempotency / robustness for [ThemeService.initialize].
///
/// The theme used to be persisted as an enum *index*; it is now a stable enum
/// *name*. `initialize()` migrates the old integer to the new name key, drops
/// the old key, and — crucially — must be a no-op on every subsequent launch
/// and must never throw on an out-of-range or unknown stored value. These are
/// the properties a migration has to guarantee: run-once, run-again-safe, and
/// junk-tolerant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ThemeService();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

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
}
