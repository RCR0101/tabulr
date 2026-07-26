import 'dart:math';

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

    test('the optional course index matches the linear scan', () {
      // The "check all" flow passes a prebuilt index for speed; it must not
      // change the answer versus the default linear _findCourse.
      final examDate = DateTime(2026, 3, 10);
      final newCourse = makeCourse(
        courseCode: 'CS F111',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        midSemExam: makeExam(date: examDate, timeSlot: TimeSlot.MS1),
      );
      final existing = makeCourse(
        courseCode: 'MATH F111',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
        // same slot → exam clash
        midSemExam: makeExam(date: examDate, timeSlot: TimeSlot.MS1),
      );
      final current = [
        makeSelectedSection(
          courseCode: 'MATH F111',
          sectionId: 'L1',
          section: existing.sections.first,
        ),
      ];
      final catalog = [newCourse, existing];
      final index = {for (final c in catalog) c.courseCode: c};

      final linear = ClashDetector.findSafeCombination(newCourse, current, catalog);
      final indexed =
          ClashDetector.findSafeCombination(newCourse, current, catalog, index);

      // Both must see the exam clash and report no safe combination.
      expect(linear, isNull);
      expect(indexed, linear);
    });
  });

  // ── Property / metamorphic stress ────────────────────────────────────
  //
  // The groups above pin specific inputs to specific outputs. These run
  // hundreds of randomised timetables and assert *invariants* that must hold
  // for every one of them, checked against an independent brute-force oracle.
  // Each property re-derives its cases from a fixed seed, so a failure is
  // reproducible: the seed and the offending selection are printed.

  // Runs [body] over [trials] random selections and records timing; rethrows
  // (with the seed already embedded by the body) so the test fails loudly.
  void property(String name, void Function(int trial, Random r) body,
      {int trials = 500}) {
    test(name, () {
      final sw = Stopwatch()..start();
      try {
        for (var i = 0; i < trials; i++) {
          body(i, Random(0x5EED + i));
        }
        sw.stop();
        _record(name, true, sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        _record(name, false, sw.elapsedMilliseconds, e.toString());
        rethrow;
      }
    });
  }

  group('ClashDetector invariants', () {
    property('regular-class clash iff two sections share a day+hour slot',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final warnings = ClashDetector.detectClashes(selection, catalog);
      final hasClassWarning =
          warnings.any((w) => w.type == ClashType.regularClass);
      final oracle = _anyPairSharesSlot(selection);

      expect(hasClassWarning, oracle,
          reason: 'seed=${0x5EED + trial} '
              'detector=$hasClassWarning oracle=$oracle\n'
              '${_describe(selection)}');
    });

    property('one regular-class warning per over-booked grid cell',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final classWarnings = ClashDetector.detectClashes(selection, catalog)
          .where((w) => w.type == ClashType.regularClass)
          .length;

      expect(classWarnings, _overbookedCells(selection),
          reason: 'seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('exam-clash warnings match same-day/same-slot course groups',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);
      final byCode = {for (final c in catalog) c.courseCode: c};

      final warnings = ClashDetector.detectClashes(selection, catalog);
      final mid =
          warnings.where((w) => w.type == ClashType.midSemExam).length;
      final end =
          warnings.where((w) => w.type == ClashType.endSemExam).length;

      expect(mid, _examClashGroups(selection, byCode, isMid: true),
          reason: 'midsem seed=${0x5EED + trial}\n${_describe(selection)}');
      expect(end, _examClashGroups(selection, byCode, isMid: false),
          reason: 'endsem seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('detectClashes is order-independent', (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);
      final shuffled = [...selection]..shuffle(r);

      final a = _signature(ClashDetector.detectClashes(selection, catalog));
      final b = _signature(ClashDetector.detectClashes(shuffled, catalog));

      expect(b, a,
          reason: 'seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('detectClashes is deterministic (pure)', (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final a = _signature(ClashDetector.detectClashes(selection, catalog));
      final b = _signature(ClashDetector.detectClashes(selection, catalog));

      expect(b, a, reason: 'seed=${0x5EED + trial}');
    });

    property('checkScheduleConflicts flags exactly a shared slot with the set',
        (trial, r) {
      // The incremental gatekeeper must report a class conflict iff the new
      // section shares a grid cell with any already-selected section — whether
      // or not that cell was already over-booked by others.
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final accepted = <SelectedSection>[];
      for (final s in selection) {
        final incrementalClash =
            ClashDetector.checkScheduleConflicts(s.section, accepted).isNotEmpty;
        final newSlots = _slotsOf(s.section);
        final oracle =
            accepted.any((a) => _slotsOf(a.section).any(newSlots.contains));

        expect(incrementalClash, oracle,
            reason: 'seed=${0x5EED + trial} adding ${s.courseCode}-${s.sectionId}\n'
                '${_describe([...accepted, s])}');
        accepted.add(s);
      }
    });

    test('empty selection has no clashes', () {
      expect(ClashDetector.detectClashes(const [], _randomCatalog(Random(1))),
          isEmpty);
    });
  });
}



// ── Random generators (no internal self-overlap: each section's schedule
// entries use distinct hours, so a section can never clash with itself) ──────

const _days = DayOfWeek.values;
const _midSlots = [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4];
const _compSlots = [TimeSlot.FN, TimeSlot.AN];

Section _randomSection(Random r, String id, SectionType type) {
  final entryCount = 1 + r.nextInt(2); // 1–2 schedule entries
  final hours = <int>{};
  while (hours.length < entryCount) {
    hours.add(1 + r.nextInt(9)); // hours 1..9, distinct across entries
  }
  final schedule = hours.map((h) {
    final dayCount = 1 + r.nextInt(3);
    final days = <DayOfWeek>{};
    while (days.length < dayCount) {
      days.add(_days[r.nextInt(_days.length)]);
    }
    return ScheduleEntry(days: days.toList(), hours: [h]);
  }).toList();
  return Section(
    sectionId: id,
    type: type,
    instructor: 'P',
    room: 'R',
    schedule: schedule,
  );
}

ExamSchedule? _randomExam(Random r, List<TimeSlot> slots) {
  if (r.nextInt(3) == 0) return null; // ~1/3 of courses have no such exam
  // Tight date window so collisions are frequent; midnight, as real data is.
  return ExamSchedule(
    date: DateTime(2026, 3, 1 + r.nextInt(4)),
    timeSlot: slots[r.nextInt(slots.length)],
  );
}

List<Course> _randomCatalog(Random r) {
  final n = 3 + r.nextInt(6); // 3–8 courses
  final courses = <Course>[];
  for (var i = 0; i < n; i++) {
    final types = <SectionType>{SectionType.L};
    if (r.nextBool()) types.add(SectionType.P);
    if (r.nextBool()) types.add(SectionType.T);
    final sections = <Section>[];
    var s = 0;
    for (final t in types) {
      final count = 1 + r.nextInt(2);
      for (var k = 0; k < count; k++) {
        sections.add(_randomSection(r, '${t.name}${s++}', t));
      }
    }
    courses.add(Course(
      courseCode: 'C$i',
      courseTitle: 'C$i',
      lectureCredits: 3,
      practicalCredits: 0,
      totalCredits: 3,
      sections: sections,
      midSemExam: _randomExam(r, _midSlots),
      endSemExam: _randomExam(r, _compSlots),
    ));
  }
  return courses;
}

List<SelectedSection> _randomSelection(Random r, List<Course> catalog) {
  final selection = <SelectedSection>[];
  for (final c in catalog) {
    if (r.nextInt(4) == 0) continue; // skip ~1/4 of courses entirely
    for (final section in c.sections) {
      if (r.nextBool()) {
        selection.add(SelectedSection(
          courseCode: c.courseCode,
          sectionId: section.sectionId,
          section: section,
        ));
      }
    }
  }
  return selection;
}

// ── Independent oracles ──────────────────────────────────────────────────────

Set<String> _slotsOf(Section s) {
  final slots = <String>{};
  for (final e in s.schedule) {
    for (final d in e.days) {
      for (final h in e.hours) {
        slots.add('${d.name}_$h');
      }
    }
  }
  return slots;
}

bool _anyPairSharesSlot(List<SelectedSection> sel) {
  for (var i = 0; i < sel.length; i++) {
    final a = _slotsOf(sel[i].section);
    for (var j = i + 1; j < sel.length; j++) {
      if (_slotsOf(sel[j].section).any(a.contains)) return true;
    }
  }
  return false;
}

/// Number of grid cells occupied by more than one selected section — the count
/// the detector emits one warning apiece for.
int _overbookedCells(List<SelectedSection> sel) {
  final counts = <String, int>{};
  for (final ss in sel) {
    for (final slot in _slotsOf(ss.section)) {
      counts[slot] = (counts[slot] ?? 0) + 1;
    }
  }
  return counts.values.where((c) => c > 1).length;
}

/// Number of (date, slot) groups holding ≥2 distinct courses for the given
/// exam type — one clash warning is expected per group.
int _examClashGroups(
  List<SelectedSection> sel,
  Map<String, Course> byCode, {
  required bool isMid,
}) {
  final groups = <String, Set<String>>{};
  for (final ss in sel) {
    final course = byCode[ss.courseCode];
    if (course == null) continue;
    final exam = isMid ? course.midSemExam : course.endSemExam;
    if (exam == null) continue;
    final key = '${exam.date.toIso8601String()}_${exam.timeSlot}';
    groups.putIfAbsent(key, () => <String>{}).add(course.courseCode);
  }
  return groups.values.where((codes) => codes.length > 1).length;
}

/// Stable, order-independent fingerprint of a warning list.
List<String> _signature(List<ClashWarning> warnings) {
  final sig = warnings
      .map((w) =>
          '${w.type}|${(w.conflictingCourses.toList()..sort()).join(",")}')
      .toList()
    ..sort();
  return sig;
}

String _describe(List<SelectedSection> sel) => sel
    .map((s) => '${s.courseCode}-${s.sectionId}:${_slotsOf(s.section).toList()..sort()}')
    .join('\n');
