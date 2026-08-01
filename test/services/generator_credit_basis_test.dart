import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_generator.dart';

import '../helpers/test_data.dart';

/// A course the booklet prints only in contact hours — Pilani's U-series.
Course hoursCourse(String code, {double hours = 9, int hour = 4}) =>
    Course.fromJson({
      'courseCode': code,
      'courseTitle': code,
      'total_credits': 0,
      'total_credit_hours': hours,
      'com_codes': [5000 + hour],
      'sections': [
        makeSection(
                sectionId: 'L1',
                days: [DayOfWeek.M, DayOfWeek.W],
                hours: [hour])
            .toJson(),
      ],
    });

Course unitsCourse(String code, {double units = 3, int hour = 6}) =>
    Course.fromJson({
      'courseCode': code,
      'courseTitle': code,
      'total_credits': units,
      'sections': [
        makeSection(
                sectionId: 'L1',
                days: [DayOfWeek.T, DayOfWeek.Th],
                hours: [hour])
            .toJson(),
      ],
    });

void main() {
  group('generator credit basis', () {
    test('a credit-hours run never picks up a credits optional', () async {
      // The failure this prevents: a generated timetable a student cannot
      // register for, because half of it is on the other basis.
      final courses = [
        hoursCourse('CHEM U101', hours: 7, hour: 1),
        hoursCourse('MATH U101', hours: 10, hour: 2),
        unitsCourse('CS F211', hour: 6),
        unitsCourse('ECON F211', hour: 7),
      ];

      final generated = await TimetableGenerator.generateTimetables(
        courses,
        TimetableConstraints(
          creditBasis: CreditBasis.hours,
          mandatoryCourses: ['CHEM U101'],
          optionalCourses: ['MATH U101', 'CS F211', 'ECON F211'],
        ),
        maxTimetables: 20,
      );

      expect(generated, isNotEmpty);
      for (final tt in generated) {
        final codes = tt.sections.map((s) => s.courseCode).toSet();
        expect(codes.contains('CS F211'), isFalse,
            reason: 'a credits course reached a credit-hours timetable');
        expect(codes.contains('ECON F211'), isFalse,
            reason: 'a credits course reached a credit-hours timetable');
      }
    });

    test('the basis is the run\'s, not inferred from what got picked', () async {
      // Asking for a credits run with an hours course mandatory must not
      // quietly become an hours run: the screen's toggle decides, and the
      // mismatch shows up as the course contributing nothing rather than as a
      // silently switched timetable.
      final generated = await TimetableGenerator.generateTimetables(
        [hoursCourse('CHEM U101', hours: 7, hour: 1)],
        TimetableConstraints(
            creditBasis: CreditBasis.units, mandatoryCourses: ['CHEM U101']),
        maxTimetables: 5,
      );
      expect(generated.first.totalCredits, 0);
    });

    test('a credits run never picks up a credit-hours optional', () async {
      final courses = [
        unitsCourse('CS F211', hour: 6),
        unitsCourse('ECON F211', hour: 7),
        hoursCourse('CHEM U101', hours: 7, hour: 1),
      ];

      final generated = await TimetableGenerator.generateTimetables(
        courses,
        TimetableConstraints(
          mandatoryCourses: ['CS F211'],
          optionalCourses: ['ECON F211', 'CHEM U101'],
        ),
        maxTimetables: 20,
      );

      expect(generated, isNotEmpty);
      for (final tt in generated) {
        expect(tt.sections.map((s) => s.courseCode), isNot(contains('CHEM U101')));
      }
      // The same-basis optional still gets in, or this test would pass by
      // simply generating nothing.
      expect(
        generated.any((tt) =>
            tt.sections.map((s) => s.courseCode).contains('ECON F211')),
        isTrue,
      );
    });

    test('credit hours are counted, not read as zero units', () async {
      final generated = await TimetableGenerator.generateTimetables(
        [hoursCourse('CHEM U101', hours: 7, hour: 1)],
        TimetableConstraints(
            creditBasis: CreditBasis.hours, mandatoryCourses: ['CHEM U101']),
        maxTimetables: 5,
      );

      expect(generated, isNotEmpty);
      expect(generated.first.totalCredits, 7);
    });

    test('a credit-hours run stops at the credit-hours cap', () async {
      // The regression this pins: the optional loop skipped its cap check
      // whenever the basis was not units, so a 2026 run packed a timetable
      // past 70 contact hours. 20 + six 12s is 92 if nothing stops it.
      final courses = [
        hoursCourse('CORE U100', hours: 20, hour: 1),
        for (var i = 0; i < 6; i++)
          hoursCourse('OPT U10$i', hours: 12, hour: 2 + i),
      ];

      final generated = await TimetableGenerator.generateTimetables(
        courses,
        TimetableConstraints(
          creditBasis: CreditBasis.hours,
          mandatoryCourses: ['CORE U100'],
          optionalCourses: [for (var i = 0; i < 6; i++) 'OPT U10$i'],
        ),
        maxTimetables: 5,
      );

      expect(generated, isNotEmpty);
      for (final tt in generated) {
        expect(tt.totalCredits, lessThanOrEqualTo(AppLimits.semesterCreditHourCap),
            reason: 'the 70-hour ceiling applies to an hours run too');
      }
      // Optionals still get picked, or a generator that returned the bare core
      // every time would pass this without ever exercising the cap.
      expect(generated.first.totalCredits, greaterThan(20));
    });

    test('an explicit maxCredits overrides the basis default', () async {
      // maxCredits used to sit behind `capFor(basis) ?? …`, which never fell
      // through — the caller's ceiling was silently discarded.
      final generated = await TimetableGenerator.generateTimetables(
        [
          hoursCourse('CORE U100', hours: 20, hour: 1),
          hoursCourse('OPT U101', hours: 12, hour: 2),
        ],
        TimetableConstraints(
          creditBasis: CreditBasis.hours,
          mandatoryCourses: ['CORE U100'],
          optionalCourses: ['OPT U101'],
          maxCredits: 25,
        ),
        maxTimetables: 5,
      );

      expect(generated, isNotEmpty);
      for (final tt in generated) {
        expect(tt.sections.map((s) => s.courseCode), isNot(contains('OPT U101')),
            reason: '20 + 12 breaks the caller\'s 25, well under the 70 default');
      }
    });
  });
}
