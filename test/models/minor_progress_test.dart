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
    needsReview: false,
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
}
