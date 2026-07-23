import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/timetable_service.dart';

import '../helpers/test_data.dart';

/// Builds a timetable whose [availableCourses] is the "fresh catalogue" and
/// whose [selectedSections] are what the student had saved.
Timetable _timetable({
  required List<Course> catalogue,
  required List<SelectedSection> selections,
}) {
  return Timetable(
    id: 't1',
    name: 'T',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    campus: Campus.pilani,
    availableCourses: catalogue,
    selectedSections: selections,
    clashWarnings: [],
  );
}

void main() {
  group('reconcileSelections', () {
    test('no changes when saved section matches the catalogue', () {
      final section = makeSection(sectionId: 'L1', room: 'F101');
      final tt = _timetable(
        catalogue: [makeCourse(sections: [section])],
        selections: [
          makeSelectedSection(sectionId: 'L1', section: section),
        ],
      );

      final report = TimetableService.reconcileSelections(tt);

      expect(report.hasChanges, isFalse);
      expect(report.changes, isEmpty);
    });

    test('detects a room change and rewrites the embedded section in place', () {
      final saved = makeSection(sectionId: 'L1', room: 'F101');
      final fresh = makeSection(sectionId: 'L1', room: 'G201');
      final tt = _timetable(
        catalogue: [makeCourse(sections: [fresh])],
        selections: [
          makeSelectedSection(sectionId: 'L1', section: saved),
        ],
      );

      final report = TimetableService.reconcileSelections(tt);

      expect(report.updatedCount, 1);
      expect(report.removedCount, 0);
      expect(report.changes.single.changedFields, ['Room']);
      // The selection now carries the corrected room.
      expect(tt.selectedSections.single.section.room, 'G201');
    });

    test('detects instructor and timing changes together', () {
      final saved = makeSection(
        sectionId: 'L1',
        instructor: 'Prof A',
        days: [DayOfWeek.M],
        hours: [1],
      );
      final fresh = makeSection(
        sectionId: 'L1',
        instructor: 'Prof B',
        days: [DayOfWeek.T],
        hours: [3],
      );
      final tt = _timetable(
        catalogue: [makeCourse(sections: [fresh])],
        selections: [
          makeSelectedSection(sectionId: 'L1', section: saved),
        ],
      );

      final report = TimetableService.reconcileSelections(tt);

      expect(report.changes.single.changedFields,
          containsAll(['Instructor', 'Timing']));
    });

    test('timing compare is order-insensitive across schedule entries', () {
      final saved = Section(
        sectionId: 'L1',
        type: SectionType.L,
        instructor: 'Prof A',
        room: 'F101',
        schedule: [
          ScheduleEntry(days: [DayOfWeek.M], hours: [1]),
          ScheduleEntry(days: [DayOfWeek.W], hours: [2]),
        ],
      );
      // Same (day, hour) slots, expressed as one merged entry in a new order.
      final fresh = Section(
        sectionId: 'L1',
        type: SectionType.L,
        instructor: 'Prof A',
        room: 'F101',
        schedule: [
          ScheduleEntry(days: [DayOfWeek.W], hours: [2]),
          ScheduleEntry(days: [DayOfWeek.M], hours: [1]),
        ],
      );
      final tt = _timetable(
        catalogue: [makeCourse(sections: [fresh])],
        selections: [
          makeSelectedSection(sectionId: 'L1', section: saved),
        ],
      );

      expect(TimetableService.reconcileSelections(tt).hasChanges, isFalse);
    });

    test('flags a removed section but keeps the selection', () {
      final saved = makeSection(sectionId: 'L1');
      // Catalogue now only offers L2 for this course.
      final tt = _timetable(
        catalogue: [
          makeCourse(sections: [makeSection(sectionId: 'L2')]),
        ],
        selections: [
          makeSelectedSection(sectionId: 'L1', section: saved),
        ],
      );

      final report = TimetableService.reconcileSelections(tt);

      expect(report.removedCount, 1);
      expect(report.changes.single.isRemoved, isTrue);
      // The selection is never dropped.
      expect(tt.selectedSections, hasLength(1));
    });

    test('flags a section whose whole course is gone from the catalogue', () {
      final tt = _timetable(
        catalogue: [makeCourse(courseCode: 'MATH F111')],
        selections: [
          makeSelectedSection(courseCode: 'CS F111', sectionId: 'L1'),
        ],
      );

      final report = TimetableService.reconcileSelections(tt);

      expect(report.removedCount, 1);
      expect(report.changes.single.courseCode, 'CS F111');
      expect(tt.selectedSections, hasLength(1));
    });
  });
}
