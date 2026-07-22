import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/models/prerequisite.dart';
import 'package:timetable_maker/models/prerequisite_status.dart';

import 'academic_record_test.dart' show recordOf;

CoursePrerequisites courseWith(
  List<(String, String)> prereqs, {
  String? allOne,
}) {
  return CoursePrerequisites(
    courseCode: 'CS F320',
    prereqs: [
      for (final (code, type) in prereqs)
        Prerequisite(courseCode: code, type: type),
    ],
    hasPrerequisites: prereqs.isNotEmpty,
    allOne: allOne,
  );
}

void main() {
  group('PrerequisiteStatus', () {
    test('verdict is unknown without a record, never negative', () {
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre')]),
        AcademicRecord.empty,
      );
      expect(status.isMet, isNull);
    });

    test('verdict is unknown when the course has no prerequisites', () {
      final status = PrerequisiteStatus.of(
        courseWith([]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isNull);
    });

    test('met once every pre requirement is cleared', () {
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre'), ('CS F213', 'pre')]),
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'C', credits: 3),
        }),
      );
      expect(status.isMet, isTrue);
      expect(status.outstanding, isEmpty);
      expect(status.cleared, hasLength(2));
    });

    test('unmet while a pre requirement is outstanding', () {
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre'), ('CS F213', 'pre')]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isFalse);
      expect(status.outstanding.single.courseCode, 'CS F213');
    });

    test('a failed prerequisite does not count as cleared', () {
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre')]),
        recordOf({'CS F211': (grade: 'E', credits: 3)}),
      );
      expect(status.isMet, isFalse);
      expect(status.outstanding.single.courseCode, 'CS F211');
    });

    test('a co/pre requirement is advice, not a blocker', () {
      // It can be taken in the same semester, so it must not make isMet false.
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre'), ('MATH F211', 'co/pre')]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
      expect(status.concurrent.single.courseCode, 'MATH F211');
    });

    test('an unrecorded requirement type never declares you blocked', () {
      // Guessing from data that cannot describe the rule would be worse than
      // staying quiet, so it surfaces separately instead.
      final status = PrerequisiteStatus.of(
        courseWith([('CS F211', 'pre'), ('PHY F110', 'nan')]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
      expect(status.unclear.single.courseCode, 'PHY F110');
    });

    test('any one of the alternatives suffices when all_one is "one"', () {
      final status = PrerequisiteStatus.of(
        courseWith(
          [('CS F211', 'pre'), ('CS F213', 'pre')],
          allOne: 'one',
        ),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.anyOneSuffices, isTrue);
      expect(status.isMet, isTrue);
      // The other is still listed, it just doesn't block.
      expect(status.outstanding.single.courseCode, 'CS F213');
    });

    test('"one" is still unmet when none of the alternatives is cleared', () {
      final status = PrerequisiteStatus.of(
        courseWith(
          [('CS F211', 'pre'), ('CS F213', 'pre')],
          allOne: 'one',
        ),
        recordOf({'MATH F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isFalse);
    });
  });
}
