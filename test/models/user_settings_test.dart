import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/user_settings.dart';
import 'package:timetable_maker/widgets/timetable_widget.dart';
import 'package:timetable_maker/services/ui/theme_service.dart' as theme_service;

void main() {
  group('TimetableSettings', () {
    test('fromJson -> toJson roundtrip', () {
      const settings = TimetableSettings(
        size: TimetableSize.large,
        layout: TimetableLayout.horizontal,
      );

      final json = settings.toJson();
      final restored = TimetableSettings.fromJson(json);

      expect(restored.size, TimetableSize.large);
      expect(restored.layout, TimetableLayout.horizontal);
    });

    test('defaultSettings uses medium and vertical', () {
      final settings = TimetableSettings.defaultSettings();
      expect(settings.size, TimetableSize.medium);
      expect(settings.layout, TimetableLayout.vertical);
    });

    test('copyWith overrides size only', () {
      const original = TimetableSettings(
        size: TimetableSize.compact,
        layout: TimetableLayout.vertical,
      );
      final copied = original.copyWith(size: TimetableSize.extraLarge);

      expect(copied.size, TimetableSize.extraLarge);
      expect(copied.layout, TimetableLayout.vertical);
    });

    test('fromJson with unknown values uses defaults', () {
      final settings = TimetableSettings.fromJson({
        'size': 'TimetableSize.doesNotExist',
        'layout': 'TimetableLayout.doesNotExist',
      });

      expect(settings.size, TimetableSize.medium);
      expect(settings.layout, TimetableLayout.vertical);
    });
  });

  group('UserSettings', () {
    test('defaultSettings has expected values', () {
      final settings = UserSettings.defaultSettings('user-1');

      expect(settings.userId, 'user-1');
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.themeVariant, theme_service.AppTheme.githubDark);
      expect(settings.sortOrder, TimetableListSortOrder.dateModifiedDesc);
      expect(settings.timetableSettings, isEmpty);
      expect(settings.customTimetableOrder, isEmpty);
      expect(settings.dontShowBottomDisclaimer, isFalse);
    });

    test('toJson -> fromJson roundtrip', () {
      final settings = UserSettings(
        userId: 'user-1',
        themeMode: ThemeMode.dark,
        themeVariant: theme_service.AppTheme.githubDark,
        sortOrder: TimetableListSortOrder.alphabeticalAsc,
        timetableSettings: {
          'tt-1': const TimetableSettings(
            size: TimetableSize.large,
            layout: TimetableLayout.horizontal,
          ),
        },
        customTimetableOrder: ['tt-1', 'tt-2'],
        dontShowBottomDisclaimer: true,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final json = settings.toJson();
      final restored = UserSettings.fromJson(json);

      expect(restored.userId, 'user-1');
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.sortOrder, TimetableListSortOrder.alphabeticalAsc);
      expect(restored.timetableSettings['tt-1']!.size, TimetableSize.large);
      expect(restored.customTimetableOrder, ['tt-1', 'tt-2']);
      expect(restored.dontShowBottomDisclaimer, isTrue);
    });

    test('copyWith overrides specified fields', () {
      final original = UserSettings.defaultSettings('user-1');
      final copied = original.copyWith(
        themeMode: ThemeMode.light,
        dontShowBottomDisclaimer: true,
      );

      expect(copied.themeMode, ThemeMode.light);
      expect(copied.dontShowBottomDisclaimer, isTrue);
      expect(copied.userId, 'user-1');
      expect(copied.sortOrder, TimetableListSortOrder.dateModifiedDesc);
    });

    test('getTimetableSettings returns default for unknown id', () {
      final settings = UserSettings.defaultSettings('user-1');
      final ttSettings = settings.getTimetableSettings('nonexistent');

      expect(ttSettings.size, TimetableSize.medium);
      expect(ttSettings.layout, TimetableLayout.vertical);
    });

    test('updateTimetableSettings adds new entry', () {
      final settings = UserSettings.defaultSettings('user-1');
      final updated = settings.updateTimetableSettings(
        'tt-1',
        const TimetableSettings(size: TimetableSize.large, layout: TimetableLayout.horizontal),
      );

      expect(updated.timetableSettings.containsKey('tt-1'), isTrue);
      expect(updated.timetableSettings['tt-1']!.size, TimetableSize.large);
    });

    test('removeTimetableSettings removes entry and custom order', () {
      final settings = UserSettings(
        userId: 'user-1',
        themeMode: ThemeMode.system,
        themeVariant: theme_service.AppTheme.githubDark,
        sortOrder: TimetableListSortOrder.custom,
        timetableSettings: {
          'tt-1': TimetableSettings.defaultSettings(),
          'tt-2': TimetableSettings.defaultSettings(),
        },
        customTimetableOrder: ['tt-1', 'tt-2'],
        lastUpdated: DateTime(2026, 1, 1),
      );

      final removed = settings.removeTimetableSettings('tt-1');

      expect(removed.timetableSettings.containsKey('tt-1'), isFalse);
      expect(removed.timetableSettings.containsKey('tt-2'), isTrue);
      expect(removed.customTimetableOrder, ['tt-2']);
    });

    test('fromJson with missing fields uses defaults', () {
      final settings = UserSettings.fromJson({
        'userId': 'user-1',
        'lastUpdated': '2026-01-01T00:00:00.000',
      });

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.sortOrder, TimetableListSortOrder.dateModifiedDesc);
      expect(settings.timetableSettings, isEmpty);
    });
  });
}
