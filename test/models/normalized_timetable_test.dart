import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/normalized_timetable.dart';
import 'package:timetable_maker/services/data/campus_service.dart';
import '../helpers/test_data.dart';

void main() {
  group('SectionReference', () {
    test('fromJson -> toJson roundtrip', () {
      final ref = SectionReference(courseCode: 'CS F111', sectionId: 'L1');
      final json = ref.toJson();
      final restored = SectionReference.fromJson(json);

      expect(restored.courseCode, 'CS F111');
      expect(restored.sectionId, 'L1');
    });

    test('equality operator', () {
      final a = SectionReference(courseCode: 'CS F111', sectionId: 'L1');
      final b = SectionReference(courseCode: 'CS F111', sectionId: 'L1');
      final c = SectionReference(courseCode: 'CS F111', sectionId: 'L2');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      final a = SectionReference(courseCode: 'CS F111', sectionId: 'L1');
      final b = SectionReference(courseCode: 'CS F111', sectionId: 'L1');

      expect(a.hashCode, b.hashCode);
    });

    test('toString returns readable format', () {
      final ref = SectionReference(courseCode: 'CS F111', sectionId: 'L1');
      expect(ref.toString(), 'CS F111-L1');
    });
  });

  group('TimetableUpdateBatch', () {
    test('isEmpty when no adds or removes', () {
      final batch = TimetableUpdateBatch(
        timetableId: 'tt-1',
        sectionsToAdd: [],
        sectionsToRemove: [],
      );
      expect(batch.isEmpty, isTrue);
    });

    test('not isEmpty when sections to add', () {
      final batch = TimetableUpdateBatch(
        timetableId: 'tt-1',
        sectionsToAdd: [SectionReference(courseCode: 'CS F111', sectionId: 'L1')],
        sectionsToRemove: [],
      );
      expect(batch.isEmpty, isFalse);
    });

    test('not isEmpty when metadata updates present', () {
      final batch = TimetableUpdateBatch(
        timetableId: 'tt-1',
        sectionsToAdd: [],
        sectionsToRemove: [],
        metadataUpdates: {'name': 'New Name'},
      );
      expect(batch.isEmpty, isFalse);
    });
  });

  group('NormalizedTimetable', () {
    test('fromJson -> toJson roundtrip', () {
      final tt = NormalizedTimetable(
        id: 'tt-1',
        name: 'My Timetable',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
        selectedSections: [
          SectionReference(courseCode: 'CS F111', sectionId: 'L1'),
          SectionReference(courseCode: 'MATH F112', sectionId: 'T1'),
        ],
        clashWarnings: [],
        projectCount: 2,
      );

      final json = tt.toJson();
      final restored = NormalizedTimetable.fromJson(json);

      expect(restored.id, 'tt-1');
      expect(restored.name, 'My Timetable');
      expect(restored.selectedSections.length, 2);
      expect(restored.projectCount, 2);
    });

    test('fromLegacyTimetable extracts section references', () {
      final courses = twoCourseNoClash();
      final legacy = Timetable(
        id: 'tt-1',
        name: 'Legacy TT',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        campus: Campus.hyderabad,
        availableCourses: courses,
        selectedSections: [
          SelectedSection(
            courseCode: 'CS F111',
            sectionId: 'L1',
            section: courses[0].sections[0],
          ),
        ],
        clashWarnings: [],
      );

      final normalized = NormalizedTimetable.fromLegacyTimetable(legacy);

      expect(normalized.id, 'tt-1');
      expect(normalized.name, 'Legacy TT');
      expect(normalized.selectedSections.length, 1);
      expect(normalized.selectedSections.first.courseCode, 'CS F111');
      expect(normalized.selectedSections.first.sectionId, 'L1');
    });

    test('toLegacyTimetable resolves sections from course list', () {
      final courses = twoCourseNoClash();
      final normalized = NormalizedTimetable(
        id: 'tt-1',
        name: 'Test',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        selectedSections: [
          SectionReference(courseCode: 'CS F111', sectionId: 'L1'),
        ],
        clashWarnings: [],
      );

      final legacy = normalized.toLegacyTimetable(courses);

      expect(legacy.selectedSections.length, 1);
      expect(legacy.selectedSections.first.section.instructor, isNotEmpty);
    });

    test('toLegacyTimetable throws for missing course', () {
      final normalized = NormalizedTimetable(
        id: 'tt-1',
        name: 'Test',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        selectedSections: [
          SectionReference(courseCode: 'MISSING', sectionId: 'L1'),
        ],
        clashWarnings: [],
      );

      expect(
        () => normalized.toLegacyTimetable([]),
        throwsA(isA<Exception>()),
      );
    });

    test('roundtrip: legacy -> normalized -> legacy preserves data', () {
      final courses = twoCourseNoClash();
      final original = Timetable(
        id: 'tt-1',
        name: 'Original',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        campus: Campus.hyderabad,
        availableCourses: courses,
        selectedSections: [
          SelectedSection(
            courseCode: 'CS F111',
            sectionId: 'L1',
            section: courses[0].sections[0],
          ),
          SelectedSection(
            courseCode: 'MATH F112',
            sectionId: 'L1',
            section: courses[1].sections[0],
          ),
        ],
        clashWarnings: [],
      );

      final normalized = NormalizedTimetable.fromLegacyTimetable(original);
      final restored = normalized.toLegacyTimetable(courses);

      expect(restored.selectedSections.length, original.selectedSections.length);
      expect(restored.selectedSections[0].courseCode, 'CS F111');
      expect(restored.selectedSections[1].courseCode, 'MATH F112');
    });
  });

  group('CourseMetadata', () {
    test('fromJson -> toJson roundtrip', () {
      final meta = CourseMetadata(
        version: '1.0',
        lastUpdated: DateTime(2026, 1, 1),
        courseHashes: {'CS F111': 'abc123', 'MATH F112': 'def456'},
      );

      final json = meta.toJson();
      final restored = CourseMetadata.fromJson(json);

      expect(restored.version, '1.0');
      expect(restored.courseHashes['CS F111'], 'abc123');
      expect(restored.courseHashes.length, 2);
    });
  });
}
