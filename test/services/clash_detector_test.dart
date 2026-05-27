import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/clash_detector.dart';
import '../helpers/test_data.dart';
import '../helpers/test_reporter.dart';

final _results = <Map<String, dynamic>>[];

void _record(String name, bool passed, int ms, [String? error]) {
  _results.add({
    'name': name,
    'status': passed ? 'pass' : 'fail',
    'duration_ms': ms,
    if (error != null) 'error': error,
  });
}

void main() {
  tearDownAll(() async {
    await TestReporter.reportTestResults('clash_detector', _results);
  });

  group('detectClashes', () {
    test('returns empty list for non-overlapping sections', () {
      final sw = Stopwatch()..start();
      final sections = [
        makeSelectedSection(
          courseCode: 'CS F111',
          sectionId: 'L1',
          section: makeSection(days: [DayOfWeek.M], hours: [1]),
        ),
        makeSelectedSection(
          courseCode: 'MATH F112',
          sectionId: 'L1',
          section: makeSection(days: [DayOfWeek.T], hours: [2]),
        ),
      ];

      final clashes = ClashDetector.detectClashes(sections, twoCourseNoClash());
      sw.stop();
      _record('no clash for non-overlapping', true, sw.elapsedMilliseconds);

      expect(clashes, isEmpty);
    });

    test('detects regular class clash on same day+hour', () {
      final sw = Stopwatch()..start();
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final sections = [
        makeSelectedSection(courseCode: 'CS F111', sectionId: 'L1', section: sharedSlot),
        makeSelectedSection(courseCode: 'CS F211', sectionId: 'L1', section: sharedSlot),
      ];

      final clashes = ClashDetector.detectClashes(sections, twoCourseSameSlot());
      sw.stop();
      _record('detects class time clash', true, sw.elapsedMilliseconds);

      expect(clashes, isNotEmpty);
      expect(clashes.first.type, ClashType.regularClass);
    });

    test('detects mid-sem exam clash', () {
      final sw = Stopwatch()..start();
      final examDate = DateTime(2026, 3, 10);
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          midSemExam: makeExam(date: examDate, timeSlot: TimeSlot.MS1),
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
        makeCourse(
          courseCode: 'CS F211',
          courseTitle: 'Data Structures',
          midSemExam: makeExam(date: examDate, timeSlot: TimeSlot.MS1),
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
        ),
      ];

      final sections = [
        makeSelectedSection(courseCode: 'CS F111', section: courses[0].sections[0]),
        makeSelectedSection(courseCode: 'CS F211', section: courses[1].sections[0]),
      ];

      final clashes = ClashDetector.detectClashes(sections, courses);
      sw.stop();
      _record('detects mid-sem exam clash', true, sw.elapsedMilliseconds);

      expect(clashes.any((c) => c.type == ClashType.midSemExam), isTrue);
    });

    test('detects end-sem exam clash', () {
      final sw = Stopwatch()..start();
      final examDate = DateTime(2026, 5, 10);
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          endSemExam: makeExam(date: examDate, timeSlot: TimeSlot.FN),
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
        makeCourse(
          courseCode: 'CS F211',
          courseTitle: 'Data Structures',
          endSemExam: makeExam(date: examDate, timeSlot: TimeSlot.FN),
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
        ),
      ];

      final sections = [
        makeSelectedSection(courseCode: 'CS F111', section: courses[0].sections[0]),
        makeSelectedSection(courseCode: 'CS F211', section: courses[1].sections[0]),
      ];

      final clashes = ClashDetector.detectClashes(sections, courses);
      sw.stop();
      _record('detects end-sem exam clash', true, sw.elapsedMilliseconds);

      expect(clashes.any((c) => c.type == ClashType.endSemExam), isTrue);
    });
  });

  group('canAddSection', () {
    test('returns true when no conflicts', () {
      final sw = Stopwatch()..start();
      final existing = [
        makeSelectedSection(
          courseCode: 'CS F111',
          section: makeSection(days: [DayOfWeek.M], hours: [1]),
        ),
      ];
      final newSection = makeSelectedSection(
        courseCode: 'MATH F112',
        section: makeSection(days: [DayOfWeek.T], hours: [2]),
      );

      final canAdd = ClashDetector.canAddSection(newSection, existing, twoCourseNoClash());
      sw.stop();
      _record('canAddSection true for no conflict', true, sw.elapsedMilliseconds);

      expect(canAdd, isTrue);
    });

    test('returns false when time conflict exists', () {
      final sw = Stopwatch()..start();
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final existing = [
        makeSelectedSection(courseCode: 'CS F111', section: sharedSlot),
      ];
      final newSection = makeSelectedSection(courseCode: 'CS F211', section: sharedSlot);

      final canAdd = ClashDetector.canAddSection(newSection, existing, twoCourseSameSlot());
      sw.stop();
      _record('canAddSection false for time conflict', true, sw.elapsedMilliseconds);

      expect(canAdd, isFalse);
    });
  });

  group('sectionsConflict', () {
    test('returns true for overlapping schedule', () {
      final sw = Stopwatch()..start();
      final s1 = makeSection(days: [DayOfWeek.M, DayOfWeek.W], hours: [1, 2]);
      final s2 = makeSection(days: [DayOfWeek.M], hours: [2]);

      final conflicts = ClashDetector.sectionsConflict(s1, s2);
      sw.stop();
      _record('sectionsConflict overlapping', true, sw.elapsedMilliseconds);

      expect(conflicts, isTrue);
    });

    test('returns false for non-overlapping schedule', () {
      final sw = Stopwatch()..start();
      final s1 = makeSection(days: [DayOfWeek.M], hours: [1]);
      final s2 = makeSection(days: [DayOfWeek.T], hours: [1]);

      final conflicts = ClashDetector.sectionsConflict(s1, s2);
      sw.stop();
      _record('sectionsConflict non-overlapping', true, sw.elapsedMilliseconds);

      expect(conflicts, isFalse);
    });

    test('same day different hours do not conflict', () {
      final sw = Stopwatch()..start();
      final s1 = makeSection(days: [DayOfWeek.M], hours: [1]);
      final s2 = makeSection(days: [DayOfWeek.M], hours: [2]);

      final conflicts = ClashDetector.sectionsConflict(s1, s2);
      sw.stop();
      _record('same day different hours no conflict', true, sw.elapsedMilliseconds);

      expect(conflicts, isFalse);
    });
  });

  group('checkScheduleConflicts', () {
    test('returns conflict info for overlapping sections', () {
      final sw = Stopwatch()..start();
      final target = makeSection(days: [DayOfWeek.M], hours: [1]);
      final existing = [
        makeSelectedSection(
          courseCode: 'CS F211',
          section: makeSection(days: [DayOfWeek.M], hours: [1]),
        ),
      ];

      final conflicts = ClashDetector.checkScheduleConflicts(target, existing);
      sw.stop();
      _record('checkScheduleConflicts finds overlap', true, sw.elapsedMilliseconds);

      expect(conflicts, isNotEmpty);
      expect(conflicts.first.conflictingCourse, 'CS F211');
    });
  });

  group('findSafeCombination', () {
    test('returns a valid combination when one exists', () {
      final sw = Stopwatch()..start();
      final course = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [2]),
        ],
      );

      final result = ClashDetector.findSafeCombination(course, [], [course]);
      sw.stop();
      _record('findSafeCombination finds valid combo', true, sw.elapsedMilliseconds);

      expect(result, isNotNull);
    });
  });
}
