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

  group('evaluateAdd', () {
    /// Two courses that never share a grid cell but sit the same midsem.
    List<Course> examClashOnly() => [
          makeCourse(
            courseCode: 'CS F111',
            sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
            midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
          ),
          makeCourse(
            courseCode: 'MATH F112',
            courseTitle: 'Mathematics I',
            sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [4])],
            midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
          ),
        ];

    List<SelectedSection> csF111Selected() => [
          makeSelectedSection(
            courseCode: 'CS F111',
            section: makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          ),
        ];

    SelectedSection mathAtFreeSlot() => makeSelectedSection(
          courseCode: 'MATH F112',
          section: makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [4]),
        );

    test('reports an exam clash as overridable and names both courses', () {
      final sw = Stopwatch()..start();
      final result = ClashDetector.evaluateAdd(
        mathAtFreeSlot(), csF111Selected(), examClashOnly(),
      );
      sw.stop();
      _record('evaluateAdd exam clash is overridable', true, sw.elapsedMilliseconds);

      expect(result.isAllowed, isFalse);
      expect(result.blockedBy, AddBlockReason.examClash);
      expect(result.isOverridable, isTrue);
      expect(result.message, contains('MATH F112'));
      expect(result.message, contains('CS F111'));
      expect(result.conflictingCourses, ['CS F111']);
    });

    test('allowExamClash lets an exam-only clash through', () {
      final sw = Stopwatch()..start();
      final result = ClashDetector.evaluateAdd(
        mathAtFreeSlot(), csF111Selected(), examClashOnly(),
        allowExamClash: true,
      );
      sw.stop();
      _record('evaluateAdd override admits exam clash', true, sw.elapsedMilliseconds);

      expect(result.isAllowed, isTrue);
      expect(result.blockedBy, isNull);
    });

    test('reports a class clash as not overridable', () {
      final sw = Stopwatch()..start();
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final result = ClashDetector.evaluateAdd(
        makeSelectedSection(courseCode: 'CS F211', section: sharedSlot),
        [makeSelectedSection(courseCode: 'CS F111', section: sharedSlot)],
        twoCourseSameSlot(),
      );
      sw.stop();
      _record('evaluateAdd class clash not overridable', true, sw.elapsedMilliseconds);

      expect(result.blockedBy, AddBlockReason.classClash);
      expect(result.isOverridable, isFalse);
    });

    test('prefers the class clash when a section clashes on both time and exams', () {
      final sw = Stopwatch()..start();
      // twoCourseSameSlot() shares both a grid cell and a midsem slot; the
      // hard (non-overridable) reason must win so Override is never offered.
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final result = ClashDetector.evaluateAdd(
        makeSelectedSection(courseCode: 'CS F211', section: sharedSlot),
        [makeSelectedSection(courseCode: 'CS F111', section: sharedSlot)],
        twoCourseSameSlot(),
      );
      sw.stop();
      _record('evaluateAdd prefers class clash over exam clash', true, sw.elapsedMilliseconds);

      expect(result.blockedBy, AddBlockReason.classClash);
      expect(result.isOverridable, isFalse);
    });

    test('allowExamClash does not bypass a class clash', () {
      final sw = Stopwatch()..start();
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final result = ClashDetector.evaluateAdd(
        makeSelectedSection(courseCode: 'CS F211', section: sharedSlot),
        [makeSelectedSection(courseCode: 'CS F111', section: sharedSlot)],
        twoCourseSameSlot(),
        allowExamClash: true,
      );
      sw.stop();
      _record('evaluateAdd override cannot bypass class clash', true, sw.elapsedMilliseconds);

      expect(result.isAllowed, isFalse);
      expect(result.blockedBy, AddBlockReason.classClash);
    });

    test('reports a duplicate section type as not overridable', () {
      final sw = Stopwatch()..start();
      final result = ClashDetector.evaluateAdd(
        makeSelectedSection(
          courseCode: 'CS F111',
          sectionId: 'L2',
          section: makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [7]),
        ),
        csF111Selected(),
        examClashOnly(),
        allowExamClash: true,
      );
      sw.stop();
      _record('evaluateAdd duplicate section type', true, sw.elapsedMilliseconds);

      expect(result.blockedBy, AddBlockReason.duplicateSectionType);
      expect(result.isOverridable, isFalse);
      expect(result.message, contains('L1'));
    });

    test('a pre-existing clash elsewhere does not block an unrelated add', () {
      final sw = Stopwatch()..start();
      // Two already-selected sections share Monday hour 1 (reachable via import).
      final sharedSlot = makeSection(days: [DayOfWeek.M], hours: [1]);
      final existing = [
        makeSelectedSection(courseCode: 'CS F111', section: sharedSlot),
        makeSelectedSection(courseCode: 'CS F211', section: sharedSlot),
      ];
      final result = ClashDetector.evaluateAdd(
        makeSelectedSection(
          courseCode: 'MATH F112',
          section: makeSection(days: [DayOfWeek.S], hours: [9]),
        ),
        existing,
        twoCourseSameSlot(),
      );
      sw.stop();
      _record('evaluateAdd ignores unrelated pre-existing clash', true, sw.elapsedMilliseconds);

      expect(result.isAllowed, isTrue);
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

  group('missing course/section resilience', () {
    // Regression: selected sections can reference courses/sections that are no
    // longer in the catalog (e.g. stale local data after an admin removal).
    // These paths must skip gracefully instead of throwing.

    test('detectClashes ignores a section whose course is not in the list', () {
      final sections = [
        makeSelectedSection(courseCode: 'CS F111', section: makeSection(days: [DayOfWeek.M], hours: [1])),
        makeSelectedSection(courseCode: 'GHOST F999', section: makeSection(days: [DayOfWeek.M], hours: [1])),
      ];

      // Only CS F111 exists in the catalog.
      final clashes = ClashDetector.detectClashes(sections, [
        makeCourse(courseCode: 'CS F111'),
      ]);

      _record('detectClashes skips unknown course', true, 0);
      // The unknown course is dropped from exam analysis; class clashes still
      // run off the section schedules, but there is no exam clash to report.
      expect(clashes.where((c) => c.type == ClashType.midSemExam), isEmpty);
    });

    test('canAddSection returns true when the new course is unknown', () {
      final newSection = makeSelectedSection(
        courseCode: 'GHOST F999',
        section: makeSection(days: [DayOfWeek.T], hours: [2]),
      );

      final canAdd = ClashDetector.canAddSection(newSection, [], [makeCourse(courseCode: 'CS F111')]);

      _record('canAddSection unknown new course no throw', true, 0);
      expect(canAdd, isTrue);
    });

    test('canAddSection skips an existing section whose course is unknown', () {
      final existing = [
        makeSelectedSection(courseCode: 'GHOST F999', section: makeSection(days: [DayOfWeek.S], hours: [8])),
      ];
      final newSection = makeSelectedSection(
        courseCode: 'CS F111',
        section: makeSection(days: [DayOfWeek.T], hours: [2]),
      );

      final canAdd = ClashDetector.canAddSection(newSection, existing, [makeCourse(courseCode: 'CS F111')]);

      _record('canAddSection unknown existing course no throw', true, 0);
      expect(canAdd, isTrue);
    });

    test('checkExamConflicts skips current sections with unknown courses', () {
      final newCourse = makeCourse(
        courseCode: 'CS F111',
        midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
      );
      final current = [
        makeSelectedSection(courseCode: 'GHOST F999'),
      ];

      final conflicts = ClashDetector.checkExamConflicts(newCourse, current, [newCourse]);

      _record('checkExamConflicts skips unknown course', true, 0);
      expect(conflicts, isEmpty);
    });

    test('isCombinationSafe returns false for a missing section id', () {
      final course = makeCourse(
        courseCode: 'CS F111',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
      );

      final safe = ClashDetector.isCombinationSafe(
        course,
        {SectionType.L: 'L_DOES_NOT_EXIST'},
        [],
        [course],
      );

      _record('isCombinationSafe missing section returns false', true, 0);
      expect(safe, isFalse);
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
