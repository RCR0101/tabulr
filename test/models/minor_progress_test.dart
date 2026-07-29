import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/models/minor_progress.dart';
import 'package:timetable_maker/models/minor_programme.dart';

import 'academic_record_test.dart' show recordOf;

MinorProgramme minorOf(
  List<MinorCourse> courses, {
  int? minCourses,
}) {
  return MinorProgramme(
    id: 'cs',
    name: 'Computer Science',
    description: '',
    minCourses: minCourses,
    minUnits: null,
    groups: [MinorCourseGroup(name: 'Core', courses: courses)],
    campuses: const [],
    status: MinorStatus.verified,
  );
}

MinorCourse course(String code, {int? units = 3}) =>
    MinorCourse(code: code, title: code, units: units);

void main() {
  group('MinorProgress', () {
    final minor = minorOf(
      [course('CS F211'), course('CS F213'), course('CS F320'), course('CS F342')],
      minCourses: 3,
    );

    test('an empty record yields no progress at all', () {
      final progress = MinorProgress.of(minor, AcademicRecord.empty);
      expect(progress.hasStarted, isFalse);
      expect(progress.clearedCount, 0);
      expect(progress.cgpaInMinor, isNull);
    });

    test('counts only cleared courses toward the total', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'B', credits: 3),
          'CS F999': (grade: 'A', credits: 3), // not part of this minor
        }),
      );
      expect(progress.clearedCount, 2);
      expect(progress.clearedUnits, 6);
      expect(progress.hasStarted, isTrue);
      expect(progress.meetsCourseCount, isFalse);
    });

    test('a failed course is tracked apart, not counted as cleared', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'E', credits: 3),
        }),
      );
      expect(progress.clearedCount, 1);
      expect(progress.failed.single.code, 'CS F213');
      // Still counts as started, so the summary surfaces the repeat.
      expect(progress.hasStarted, isTrue);
    });

    test('meets the course count once the Bulletin minimum is reached', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'B', credits: 3),
          'CS F320': (grade: 'B', credits: 3),
        }),
      );
      expect(progress.meetsCourseCount, isTrue);
      expect(progress.fraction, 1.0);
    });

    test('clearing more than the minimum does not overfill the bar', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'A', credits: 3),
          'CS F320': (grade: 'A', credits: 3),
          'CS F342': (grade: 'A', credits: 3),
        }),
      );
      expect(progress.clearedCount, 4);
      expect(progress.fraction, 1.0);
    });

    test('falls back to the listed count when the Bulletin gives no minimum', () {
      final noMinimum = minorOf([course('CS F211'), course('CS F213')]);
      final progress = MinorProgress.of(
        noMinimum,
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(progress.requiredCourses, 2);
      expect(progress.fraction, 0.5);
    });

    test('flags units as a floor when a cleared course has no unit count', () {
      final partial = minorOf([course('CS F211'), course('CS F213', units: null)]);
      final progress = MinorProgress.of(
        partial,
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'A', credits: 3),
        }),
      );
      expect(progress.clearedUnits, 3);
      expect(progress.unitsAreComplete, isFalse);
    });

    test('measures CGPA across the minor, not overall', () {
      // Clause 5.02(iv) puts the 4.50 floor on the minor's own courses.
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'CS F211': (grade: 'D-', credits: 3), // 3 points
          'CS F213': (grade: 'D', credits: 3), // 4 points
        }),
      );
      expect(progress.cgpaInMinor, closeTo(3.5, 0.001));
      expect(progress.meetsCgpa, isFalse);
    });

    test('meetsCgpa is null, not false, before anything is graded', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({'MATH F211': (grade: 'A', credits: 3)}),
      );
      expect(progress.cgpaInMinor, isNull);
      expect(progress.meetsCgpa, isNull);
    });
  });

  group('alternative courses', () {
    // "PHY F212 or ECE F212 / EEE F212 / INSTR F212" is one Bulletin row: an
    // ECE student clearing their own EMT has met it.
    final emt = MinorCourse(
      code: 'PHY F212',
      title: 'Electromagnetic Theory-1',
      units: 3,
      alternatives: const ['ECE F212', 'EEE F212', 'INSTR F212'],
    );
    final minor = minorOf([emt, course('PHY F242')], minCourses: 2);

    test('clearing an alternative satisfies the requirement', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({'ECE F212': (grade: 'A', credits: 3)}),
      );
      expect(progress.clearedCount, 1);
      expect(progress.clearedUnits, 3);
    });

    test('the CGPA uses the code actually taken', () {
      // Averaging over PHY F212 — which this student never took — would find
      // no attempt and silently drop the course from the CGPA.
      final progress = MinorProgress.of(
        minor,
        recordOf({'ECE F212': (grade: 'B', credits: 3)}),
      );
      expect(progress.cgpaInMinor, closeTo(8.0, 0.001));
    });

    test('an unrelated course still does not count', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({'PHY F111': (grade: 'A', credits: 3)}),
      );
      expect(progress.clearedCount, 0);
    });

    test('passing one alternative outweighs failing another', () {
      final progress = MinorProgress.of(
        minor,
        recordOf({
          'PHY F212': (grade: 'E', credits: 3),
          'EEE F212': (grade: 'B', credits: 3),
        }),
      );
      expect(progress.clearedCount, 1);
      expect(progress.failed, isEmpty);
    });
  });

  group('group requirements', () {
    MinorProgramme split({int? coreRequired, int? electiveRequired}) =>
        MinorProgramme(
          id: 'ds',
          name: 'Data Science',
          minCourses: 5,
          groups: [
            MinorCourseGroup(
              name: 'Core Courses',
              courses: [course('BITS F464'), course('CS F320'), course('MATH F432')],
              required: coreRequired,
            ),
            MinorCourseGroup(
              name: 'Electives',
              courses: [course('CS F415'), course('CS F425'), course('CS F429')],
              required: electiveRequired,
            ),
          ],
        );

    test('a group requiring all its courses is mandatory', () {
      final minor = split(coreRequired: 3, electiveRequired: 2);
      expect(minor.groups.first.isMandatory, isTrue);
      expect(minor.groups.last.isMandatory, isFalse);
    });

    test('the core/elective split comes off the mandatory groups', () {
      final minor = split(coreRequired: 3, electiveRequired: 2);
      expect(minor.mandatoryCourses, 3);
      expect(minor.electiveCourses, 2);
    });

    test('the split is null while no group is marked mandatory', () {
      // The card falls back to "5 courses min" rather than inventing a split.
      expect(split().electiveCourses, isNull);
      expect(split().mandatoryCourses, 0);
    });

    test('enough courses but no core is not complete', () {
      // The failure the group counts exist to catch: three electives clears
      // the 5-course bar on nothing but pool courses.
      final progress = MinorProgress.of(
        split(coreRequired: 3, electiveRequired: 2),
        recordOf({
          'CS F415': (grade: 'A', credits: 3),
          'CS F425': (grade: 'A', credits: 3),
          'CS F429': (grade: 'A', credits: 3),
        }),
      );
      expect(progress.meetsGroups, isFalse);
      expect(progress.meetsCoursework, isFalse);
      expect(progress.groups.first.cleared, 0);
      expect(progress.groups.first.isSatisfied, isFalse);
      expect(progress.groups.last.isSatisfied, isTrue);
    });

    test('clearing the minimum in every group completes the minor', () {
      final progress = MinorProgress.of(
        split(coreRequired: 3, electiveRequired: 2),
        recordOf({
          'BITS F464': (grade: 'A', credits: 3),
          'CS F320': (grade: 'A', credits: 3),
          'MATH F432': (grade: 'A', credits: 3),
          'CS F415': (grade: 'A', credits: 3),
          'CS F425': (grade: 'A', credits: 3),
        }),
      );
      expect(progress.meetsCoursework, isTrue);
    });

    test('a group with no stated minimum never blocks completion', () {
      // English Studies states one total across two pools, so neither pool
      // has a figure of its own — unknown must not read as unmet.
      final progress = MinorProgress.of(
        split(coreRequired: 3),
        recordOf({
          'BITS F464': (grade: 'A', credits: 3),
          'CS F320': (grade: 'A', credits: 3),
          'MATH F432': (grade: 'A', credits: 3),
          'CS F415': (grade: 'A', credits: 3),
          'CS F425': (grade: 'A', credits: 3),
        }),
      );
      expect(progress.groups.last.isSatisfied, isNull);
      expect(progress.meetsGroups, isTrue);
    });
  });
}
