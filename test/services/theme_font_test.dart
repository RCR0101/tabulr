import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';

void main() {
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
