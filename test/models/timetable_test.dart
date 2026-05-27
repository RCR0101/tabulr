import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/campus_service.dart';
import '../helpers/test_data.dart';

void main() {
  group('SelectedSection', () {
    test('fromJson -> toJson roundtrip', () {
      final ss = makeSelectedSection(
        courseCode: 'CS F111',
        sectionId: 'L1',
        section: makeSection(days: [DayOfWeek.M, DayOfWeek.W], hours: [1, 2]),
      );

      final json = ss.toJson();
      final restored = SelectedSection.fromJson(json);

      expect(restored.courseCode, ss.courseCode);
      expect(restored.sectionId, ss.sectionId);
      expect(restored.section.instructor, ss.section.instructor);
    });
  });

  group('ClashWarning', () {
    test('fromJson -> toJson roundtrip', () {
      final warning = ClashWarning(
        type: ClashType.regularClass,
        message: 'Test clash',
        conflictingCourses: ['CS F111', 'CS F211'],
        severity: ClashSeverity.error,
      );

      final json = warning.toJson();
      final restored = ClashWarning.fromJson(json);

      expect(restored.type, ClashType.regularClass);
      expect(restored.message, 'Test clash');
      expect(restored.conflictingCourses, ['CS F111', 'CS F211']);
      expect(restored.severity, ClashSeverity.error);
    });
  });

  group('ClashType', () {
    test('all enum values serialize correctly', () {
      for (final type in ClashType.values) {
        final str = type.toString();
        final restored = ClashType.values.firstWhere((e) => e.toString() == str);
        expect(restored, type);
      }
    });
  });

  group('Timetable', () {
    test('fromJson defaults campus to hyderabad', () {
      final json = {
        'id': 'test-1',
        'name': 'My TT',
        'createdAt': '2026-05-27T10:00:00.000Z',
        'updatedAt': '2026-05-27T10:00:00.000Z',
      };

      final tt = Timetable.fromJson(json);
      expect(tt.campus, Campus.hyderabad);
    });

    test('fromJson defaults name to Untitled Timetable', () {
      final json = {
        'id': 'test-1',
        'createdAt': '2026-05-27T10:00:00.000Z',
        'updatedAt': '2026-05-27T10:00:00.000Z',
      };

      final tt = Timetable.fromJson(json);
      expect(tt.name, 'Untitled Timetable');
    });

    test('fromJson parses all campuses', () {
      for (final code in ['pilani', 'hyderabad', 'goa']) {
        final json = {
          'id': 'test',
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
          'campus': code,
        };
        final tt = Timetable.fromJson(json);
        expect(tt.campus.name, code);
      }
    });

    test('copyWith preserves unchanged fields', () {
      final original = Timetable(
        id: 'test-1',
        name: 'Original',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        campus: Campus.pilani,
        availableCourses: [],
        selectedSections: [],
        clashWarnings: [],
        shareId: 'share-123',
        projectCount: 3,
      );

      final copied = original.copyWith(name: 'Changed');
      expect(copied.name, 'Changed');
      expect(copied.id, 'test-1');
      expect(copied.campus, Campus.pilani);
      expect(copied.shareId, 'share-123');
      expect(copied.projectCount, 3);
    });

    test('copyWith shareId nullable function pattern', () {
      final original = Timetable(
        id: 'test',
        name: 'Test',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        campus: Campus.hyderabad,
        availableCourses: [],
        selectedSections: [],
        clashWarnings: [],
        shareId: 'old-share',
      );

      final cleared = original.copyWith(shareId: () => null);
      expect(cleared.shareId, isNull);

      final updated = original.copyWith(shareId: () => 'new-share');
      expect(updated.shareId, 'new-share');
    });
  });
}
