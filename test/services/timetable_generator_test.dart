import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/timetable_generator.dart';
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
    test('generates valid timetables for one mandatory course', () {
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

      final results = TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();
      _record('one mandatory course', true, sw.elapsedMilliseconds);

      expect(results, isNotEmpty);
      for (final tt in results) {
        expect(tt.sections, isNotEmpty);
        expect(tt.score, greaterThanOrEqualTo(0));
      }
    });

    test('finds the only valid combo for two clashing courses', () {
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

      final results = TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();
      _record('two courses valid combo', true, sw.elapsedMilliseconds);

      expect(results, isNotEmpty);
      // Every result must not have CS F111 L1 + MATH F112 L1 (same slot)
      for (final tt in results) {
        final codes = tt.sections.map((s) => '${s.courseCode}:${s.sectionId}').toSet();
        expect(codes.contains('CS F111:L1') && codes.contains('MATH F112:L1'), isFalse);
      }
    });

    test('throws when mandatory course missing from available', () {
      final sw = Stopwatch()..start();
      final courses = [makeCourse(courseCode: 'CS F111')];
      final constraints = TimetableConstraints(
        mandatoryCourses: ['CS F111', 'MISSING_COURSE'],
      );

      bool threw = false;
      try {
        TimetableGenerator.generateTimetables(courses, constraints);
      } on Exception {
        threw = true;
      }
      sw.stop();
      _record('throws for missing mandatory', threw, sw.elapsedMilliseconds);

      expect(threw, isTrue);
    });

    test('respects maxTimetables cap', () {
      final sw = Stopwatch()..start();
      final courses = fiveCourseRealistic();
      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      final results = TimetableGenerator.generateTimetables(
        courses, constraints,
        maxTimetables: 5,
      );
      sw.stop();
      _record('respects maxTimetables', true, sw.elapsedMilliseconds);

      expect(results.length, lessThanOrEqualTo(5));
    });

    test('results are sorted by score descending', () {
      final sw = Stopwatch()..start();
      final courses = fiveCourseRealistic();
      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      final results = TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();
      _record('sorted by score descending', true, sw.elapsedMilliseconds);

      for (int i = 1; i < results.length; i++) {
        expect(results[i].score, lessThanOrEqualTo(results[i - 1].score));
      }
    });

    test('includes optional courses when credits allow', () {
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

      final results = TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final anyHasOptional = results.any((tt) => tt.optionalCourseCodes.contains('OPT F100'));
      _record('includes optionals', anyHasOptional, sw.elapsedMilliseconds);

      expect(anyHasOptional, isTrue);
    });

    test('deduplicates identical section combos', () {
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

      final results = TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final keys = results.map((tt) =>
        (tt.sections.map((s) => '${s.courseCode}:${s.sectionId}').toList()..sort()).join('|')
      ).toSet();
      _record('deduplicates combos', keys.length == results.length, sw.elapsedMilliseconds);

      expect(keys.length, results.length);
    });
  });

  group('performance', () {
    test('generates for 5 courses within 2 seconds', () {
      final sw = Stopwatch()..start();
      final courses = fiveCourseRealistic();
      final constraints = TimetableConstraints(
        mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      );

      TimetableGenerator.generateTimetables(courses, constraints);
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      _record('5 courses generation time', ms < 2000, ms);

      expect(ms, lessThan(2000));
    });

    test('handles pathological input without hanging', () {
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

      TimetableGenerator.generateTimetables(courses, constraints, maxTimetables: 10);
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
