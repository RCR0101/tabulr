import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_generator.dart';
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
    await TestReporter.reportTestResults('timetable_generator', _results);
  });

  group('generateTimetables', () {
    test('generates valid timetables for one mandatory course', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
            makeSection(sectionId: 'T1', type: SectionType.T, days: [DayOfWeek.T], hours: [5]),
          ],
        ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();
      _record('one mandatory course', true, sw.elapsedMilliseconds);

      expect(results, isNotEmpty);
      for (final tt in results) {
        expect(tt.sections, isNotEmpty);
      }
    });

    test('finds the only valid combo for two clashing courses', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
            makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [1]),
          ],
        ),
        makeCourse(
          courseCode: 'MATH F112',
          courseTitle: 'Mathematics I',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
            makeSection(sectionId: 'L2', days: [DayOfWeek.W], hours: [1]),
          ],
        ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111', 'MATH F112'],
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();
      _record('two courses valid combo', true, sw.elapsedMilliseconds);

      expect(results, isNotEmpty);
      // Every result must not have CS F111 L1 + MATH F112 L1 (same slot)
      for (final tt in results) {
        final codes = tt.sections.map((s) => '${s.courseCode}:${s.sectionId}').toSet();
        expect(codes.contains('CS F111:L1') && codes.contains('MATH F112:L1'), isFalse);
      }
    });

    test('throws when mandatory course missing from available', () async {
      final sw = Stopwatch()..start();
      final courses = [makeCourse(courseCode: 'CS F111')];
      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111', 'MISSING_COURSE'],
      );

      bool threw = false;
      try {
        await TimetableGenerator.generateTimetables(courses, constraints);
      } on Exception {
        threw = true;
      }
      sw.stop();
      _record('throws for missing mandatory', threw, sw.elapsedMilliseconds);

      expect(threw, isTrue);
    });

    test('respects maxTimetables cap', () async {
      final sw = Stopwatch()..start();
      final courses = fiveCourseRealistic();
      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      final results = await TimetableGenerator.generateTimetables(
        courses, constraints,
        maxTimetables: 5,
      );
      sw.stop();
      _record('respects maxTimetables', true, sw.elapsedMilliseconds);

      expect(results.length, lessThanOrEqualTo(5));
    });

    test('includes optional courses when credits allow', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
        makeCourse(
          courseCode: 'OPT F100',
          courseTitle: 'Optional Course',
          lectureCredits: 2,
          practicalCredits: 0,
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
        ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
        optionalCourses: ['OPT F100'],
        maxCredits: 25,
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final anyHasOptional = results.any((tt) => tt.optionalCourseCodes.contains('OPT F100'));
      _record('includes optionals', anyHasOptional, sw.elapsedMilliseconds);

      expect(anyHasOptional, isTrue);
    });

    // The fixture above has no gaps anywhere, so its fitness is ~0 and any
    // sentinel would let the optional through. A real week has gaps — and the
    // greedy insertion compares the *whole* timetable's fitness against its
    // starting best, so a negative-fitness week used to reject every optional
    // that fit perfectly well.
    test('includes optionals even when the week already scores badly', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1, 5]),
          ],
        ),
        makeCourse(
          courseCode: 'OPT F100',
          courseTitle: 'Optional Course',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2]),
          ],
        ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
        optionalCourses: ['OPT F100'],
        maxCredits: 25,
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final anyHasOptional = results.any((tt) => tt.optionalCourseCodes.contains('OPT F100'));
      _record('optionals survive a low-fitness week', anyHasOptional, sw.elapsedMilliseconds);

      expect(anyHasOptional, isTrue,
          reason: 'the optional clashes with nothing and fits under maxCredits');
    });

    // The pruner scores on day shape alone, where every extra course can only
    // cost more — so a single global sort would hand the ranker nothing but
    // timetables that fitted no optionals at all.
    test('the pruned pool keeps optional-rich candidates', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [
            for (var i = 1; i <= 4; i++)
              makeSection(sectionId: 'L$i', days: [DayOfWeek.M], hours: [i]),
          ],
        ),
        for (var i = 0; i < 3; i++)
          makeCourse(
            courseCode: 'OPT F10$i',
            courseTitle: 'Optional $i',
            lectureCredits: 3,
            practicalCredits: 0,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2 + i * 2]),
            ],
          ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
        optionalCourses: ['OPT F100', 'OPT F101', 'OPT F102'],
        maxCredits: 25,
      );

      final results = await TimetableGenerator.generateTimetables(
        courses,
        constraints,
        maxTimetables: 6,
      );
      sw.stop();

      final best = results.fold(0, (m, tt) => max(m, tt.optionalCourseCodes.length));
      _record('pool keeps optional-rich options', best == 3, sw.elapsedMilliseconds);

      expect(best, 3, reason: 'all three optionals fit clash-free');
    });

    // Section shuffles of one elective pair are not variety. When the credit
    // cap only allows some of the shortlist, the results should show different
    // combinations of it, not thirty versions of whichever pair scored best.
    test('results offer different elective combinations, not just sections', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [
            for (var i = 1; i <= 3; i++)
              makeSection(sectionId: 'L$i', days: [DayOfWeek.M], hours: [i]),
          ],
        ),
        for (var i = 0; i < 4; i++)
          makeCourse(
            courseCode: 'OPT F10$i',
            courseTitle: 'Optional $i',
            lectureCredits: 3,
            practicalCredits: 0,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1 + i]),
            ],
          ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
        optionalCourses: ['OPT F100', 'OPT F101', 'OPT F102', 'OPT F103'],
        // Room for the core plus two electives, so which two is a real choice.
        maxCredits: 9,
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final sets = results
          .map((tt) => (tt.optionalCourseCodes.toList()..sort()).join('|'))
          .toSet();
      _record('varied elective combinations', sets.length >= 3, sw.elapsedMilliseconds);

      expect(sets.length, greaterThanOrEqualTo(3),
          reason: 'four electives competing for two slots should surface '
              'several different pairs, not one pair over and over');
    });

    test('a lone elective is offered both ways', () async {
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
        makeCourse(
          courseCode: 'OPT F100',
          lectureCredits: 3,
          practicalCredits: 0,
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
        ),
      ];
      final results = await TimetableGenerator.generateTimetables(
        courses,
        TimetableConstraints(
          mandatoryCourses: ['CS F111'],
          optionalCourses: ['OPT F100'],
          maxCredits: 25,
        ),
      );

      // Dropping it frees Tuesday entirely — a trade worth showing.
      expect(results.any((tt) => tt.optionalCourseCodes.isNotEmpty), isTrue);
      expect(results.any((tt) => tt.optionalCourseCodes.isEmpty), isTrue);
    });

    test('optionalTarget caps how many optionals are included', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          lectureCredits: 3,
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
        for (var i = 0; i < 3; i++)
          makeCourse(
            courseCode: 'OPT F10$i',
            courseTitle: 'Optional $i',
            lectureCredits: 2,
            sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2 + i])],
          ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
        optionalCourses: ['OPT F100', 'OPT F101', 'OPT F102'],
        optionalTarget: 1,
        maxCredits: 25,
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final capRespected = results.every((tt) => tt.optionalCourseCodes.length <= 1);
      _record('optionalTarget cap', capRespected, sw.elapsedMilliseconds);

      expect(results, isNotEmpty);
      expect(capRespected, isTrue);
    });

    test('deduplicates identical section combos', () async {
      final sw = Stopwatch()..start();
      final courses = [
        makeCourse(
          courseCode: 'CS F111',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          ],
        ),
      ];

      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111'],
      );

      final results = await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final keys = results.map((tt) =>
        (tt.sections.map((s) => '${s.courseCode}:${s.sectionId}').toList()..sort()).join('|')
      ).toSet();
      _record('deduplicates combos', keys.length == results.length, sw.elapsedMilliseconds);

      expect(keys.length, results.length);
    });
  });

  group('performance', () {
    test('generates for 5 courses within 2 seconds', () async {
      final sw = Stopwatch()..start();
      final courses = fiveCourseRealistic();
      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      await TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      _record('5 courses generation time', ms < 2000, ms);

      expect(ms, lessThan(2000));
    });

    test('handles pathological input without hanging', () async {
      final sw = Stopwatch()..start();
      // 6 courses with 4 sections each = 4^6 = 4096 combos (within 10k cap)
      final courses = List.generate(6, (i) => makeCourse(
        courseCode: 'COURSE_$i',
        courseTitle: 'Course $i',
        sections: List.generate(4, (j) => makeSection(
          sectionId: 'L$j',
          days: [DayOfWeek.values[j % 6]],
          hours: [(i + j) % 10 + 1],
        )),
      ));

      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      await TimetableGenerator.generateTimetables(courses, constraints, maxTimetables: 10);
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      _record('pathological input completes', ms < 10000, ms);

      expect(ms, lessThan(10000));
    });

    tearDownAll(() async {
      final perfMetrics = _results
          .where((r) => r['name'].toString().contains('time') || r['name'].toString().contains('completes'))
          .map((r) => {
            'operation': 'generator_${r['name'].toString().replaceAll(' ', '_')}',
            'duration_ms': r['duration_ms'],
            'classification': TestReporter.classify(r['duration_ms'] as int),
          })
          .toList();
      if (perfMetrics.isNotEmpty) {
        await TestReporter.reportPerfMetrics(perfMetrics);
      }
    });
  });
}
