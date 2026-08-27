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
  test(
    'old integer index migrates to the new name key and drops the old key',
    () async {
      await prefsWith({StorageKeys.selectedTheme: 1}); // 1 == draculaDark
      await service.initialize();

      expect(service.currentTheme, AppTheme.draculaDark);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(StorageKeys.selectedThemeName),
        AppTheme.draculaDark.name,
      );
      expect(
        prefs.getInt(StorageKeys.selectedTheme),
        isNull,
        reason: 'old key must be removed after migrating',
      );
    },
  );

  test(
    're-running the migration is a no-op (idempotent across launches)',
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
      expect(
        prefs.getString(StorageKeys.selectedThemeName),
        AppTheme.nordDark.name,
      );
    },
  );

  test(
    'an out-of-range or unmapped old index falls back without throwing',
    () async {
      for (final bad in [-1, 13, 999, 4]) {
        await prefsWith({StorageKeys.selectedTheme: bad});
        await service.initialize();
        expect(
          service.currentTheme,
          AppTheme.githubDark,
          reason: 'unmapped index $bad should fall back to the default',
        );
      }
    },
  );

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

  group('bundled typography', () {
    // Both type families are bundled so rendering never needs a font request.
    test('headings and body use their bundled type families', () {
      final theme = ThemeService().getLightThemeData(AppTheme.githubDark);
      final t = theme.textTheme;

      final headings = <TextStyle?>[
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
      ];
      for (final style in headings) {
        expect(style?.fontFamily, 'SpaceGrotesk');
      }
      final styles = <TextStyle?>[
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ];

      for (final style in styles) {
        expect(style?.fontFamily, 'Inter');
      }
    });

    test('dialog titles use Space Grotesk', () {
      // The one style built as a bare TextStyle rather than via the text theme
      // — it has to name the family itself.
      final theme = ThemeService().getDarkThemeData(AppTheme.githubDark);
      expect(theme.dialogTheme.titleTextStyle?.fontFamily, 'SpaceGrotesk');
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

  test('system previews use the supplied platform brightness', () async {
    await prefsWith({});
    await service.setThemeMode(ThemeMode.system);

    expect(
      service
          .getThemeData(
            AppTheme.githubDark,
            platformBrightness: Brightness.light,
          )
          .brightness,
      Brightness.light,
    );
    expect(
      service
          .getThemeData(
            AppTheme.githubDark,
            platformBrightness: Brightness.dark,
          )
          .brightness,
      Brightness.dark,
    );
  });

  test('palette names stay independent of brightness mode', () {
    expect(AppTheme.githubDark.displayName, 'GitHub');
    expect(AppTheme.solarizedDark.displayName, 'Solarized');
    expect(AppTheme.amoledDark.displayName, 'AMOLED');
  });

  group('semantic contrast', () {
    double ratio(Color a, Color b) {
      final first = a.computeLuminance() + 0.05;
      final second = b.computeLuminance() + 0.05;
      return first > second ? first / second : second / first;
    }

    for (final appTheme in AppTheme.values) {
      for (final brightness in Brightness.values) {
        test(
          '${appTheme.name} ${brightness.name} foreground pairs are readable',
          () {
            final theme =
                brightness == Brightness.light
                    ? service.getLightThemeData(appTheme)
                    : service.getDarkThemeData(appTheme);
            final scheme = theme.colorScheme;
            final pairs = <(String, Color, Color)>[
              ('surface', scheme.onSurface, scheme.surface),
              ('primary', scheme.onPrimary, scheme.primary),
              ('secondary', scheme.onSecondary, scheme.secondary),
              ('tertiary', scheme.onTertiary, scheme.tertiary),
              ('error', scheme.onError, scheme.error),
              (
                'primaryContainer',
                scheme.onPrimaryContainer,
                scheme.primaryContainer,
              ),
              (
                'secondaryContainer',
                scheme.onSecondaryContainer,
                scheme.secondaryContainer,
              ),
              (
                'tertiaryContainer',
                scheme.onTertiaryContainer,
                scheme.tertiaryContainer,
              ),
              (
                'errorContainer',
                scheme.onErrorContainer,
                scheme.errorContainer,
              ),
            ];

            for (final (role, foreground, background) in pairs) {
              expect(
                ratio(foreground, background),
                greaterThanOrEqualTo(4.5),
                reason: '${appTheme.name} ${brightness.name} $role',
              );
            }
          },
        );
      }
    }
  });
}
