import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/credit_mix.dart';
import 'package:timetable_maker/models/timetable.dart';
import '../helpers/test_data.dart';

/// A Pilani course printed twice: units under its ordinary com cod, contact
/// hours under the 2026-batch one. Same sections either way.
Course twoWayCourse(String code, {double units = 4, double hours = 12}) =>
    Course.fromJson({
      'courseCode': code,
      'total_credits': units,
      'total_credit_hours': hours,
      'com_codes': [2986, 6221],
      'variants': [
        {'com_code': 2986, 'credits': units, 'credit_hours': 0},
        {'com_code': 6221, 'credits': 0, 'credit_hours': hours},
      ],
      'sections': [],
    });

SelectedSection pick(String code, {int? comCode, String section = 'L1'}) =>
    SelectedSection(
      courseCode: code,
      sectionId: section,
      section: makeSection(sectionId: section),
      comCode: comCode,
    );

void main() {
  group('CreditMix', () {
    test('a plain timetable is all units', () {
      final catalog = [makeCourse(courseCode: 'CS F111', totalCredits: 4)];
      final mix = CreditMix.of([pick('CS F111')], catalog);

      expect(mix.isMixed, isFalse);
      expect(mix.basis, CreditBasis.units);
      expect(mix.amountFor(CreditBasis.units), 4);
      expect(mix.amountFor(CreditBasis.hours), 0);
    });

    test('the chosen com cod decides which number counts', () {
      final catalog = [twoWayCourse('CS G569')];

      final asUnits = CreditMix.of([pick('CS G569', comCode: 2986)], catalog);
      expect(asUnits.basis, CreditBasis.units);
      expect(asUnits.amountFor(CreditBasis.units), 4);

      final asHours = CreditMix.of([pick('CS G569', comCode: 6221)], catalog);
      expect(asHours.basis, CreditBasis.hours);
      expect(asHours.amountFor(CreditBasis.hours), 12);
      // The 12 must never land in the units total — that is the whole point.
      expect(asHours.amountFor(CreditBasis.units), 0);
    });

    test('units and hours together are reported as mixed, never summed', () {
      final catalog = [
        makeCourse(courseCode: 'CS F111', totalCredits: 4),
        twoWayCourse('CS G569'),
      ];
      final mix = CreditMix.of(
        [pick('CS F111'), pick('CS G569', comCode: 6221)],
        catalog,
      );

      expect(mix.isMixed, isTrue);
      expect(mix.basis, isNull);
      expect(mix.amountFor(CreditBasis.units), 4);
      expect(mix.amountFor(CreditBasis.hours), 12);
      expect(mix.coursesFor(CreditBasis.units), ['CS F111']);
      expect(mix.coursesFor(CreditBasis.hours), ['CS G569']);
    });

    test('a course is counted once however many sections are picked', () {
      final catalog = [makeCourse(courseCode: 'CS F111', totalCredits: 4)];
      final mix = CreditMix.of([
        pick('CS F111', section: 'L1'),
        pick('CS F111', section: 'P1'),
        pick('CS F111', section: 'T1'),
      ], catalog);

      expect(mix.amountFor(CreditBasis.units), 4);
      expect(mix.coursesFor(CreditBasis.units), ['CS F111']);
    });

    test('a timetable saved before com cods existed still resolves', () {
      // comCode null — every timetable saved before 2026-27. It must land on
      // the course's first variant rather than counting as nothing.
      final mix = CreditMix.of([pick('CS G569')], [twoWayCourse('CS G569')]);

      expect(mix.basis, CreditBasis.units);
      expect(mix.amountFor(CreditBasis.units), 4);
    });

    test('a course missing from the catalog contributes nothing', () {
      final mix = CreditMix.of([pick('GONE F999')], []);

      expect(mix.isMixed, isFalse);
      expect(mix.byBasis, isEmpty);
    });

    test('an hours-only course counts in hours without being asked', () {
      // Pilani CHEM U101: no unit count published, so its single variant is
      // hours and a timetable holding it is an hours timetable.
      final course = Course.fromJson({
        'courseCode': 'CHEM U101',
        'total_credits': 0,
        'total_credit_hours': 7,
        'com_codes': [5236],
        'sections': [],
      });
      final mix = CreditMix.of([pick('CHEM U101')], [course]);

      expect(mix.basis, CreditBasis.hours);
      expect(mix.amountFor(CreditBasis.hours), 7);
    });
  });
}
