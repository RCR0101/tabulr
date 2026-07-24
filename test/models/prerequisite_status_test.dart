import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/models/prerequisite.dart';
import 'package:timetable_maker/models/prerequisite_status.dart';

import 'academic_record_test.dart' show recordOf;

/// Each entry is one requirement group: a list of (code, type) options where
/// any one option satisfies the group.
CoursePrerequisites courseWith(List<List<(String, String)>> groups) {
  return CoursePrerequisites(
    courseCode: 'CS F320',
    groups: [
      for (final g in groups)
        PrerequisiteGroup([
          for (final (code, type) in g) Prerequisite(courseCode: code, type: type),
        ]),
    ],
    hasPrerequisites: groups.isNotEmpty,
  );
}

void main() {
  group('PrerequisiteStatus', () {
    test('verdict is unknown without a record, never negative', () {
      final status = PrerequisiteStatus.of(
        courseWith([[('CS F211', 'pre')]]),
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

    test('met once every pre group is cleared', () {
      final status = PrerequisiteStatus.of(
        courseWith([
          [('CS F211', 'pre')],
          [('CS F213', 'pre')],
        ]),
        recordOf({
          'CS F211': (grade: 'A', credits: 3),
          'CS F213': (grade: 'C', credits: 3),
        }),
      );
      expect(status.isMet, isTrue);
      expect(status.outstanding, isEmpty);
      expect(status.cleared, hasLength(2));
    });

    test('unmet while a pre group is outstanding', () {
      final status = PrerequisiteStatus.of(
        courseWith([
          [('CS F211', 'pre')],
          [('CS F213', 'pre')],
        ]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isFalse);
      expect(status.outstanding.single.label, 'CS F213');
    });

    test('a failed prerequisite does not count as cleared', () {
      final status = PrerequisiteStatus.of(
        courseWith([[('CS F211', 'pre')]]),
        recordOf({'CS F211': (grade: 'E', credits: 3)}),
      );
      expect(status.isMet, isFalse);
      expect(status.outstanding.single.label, 'CS F211');
    });

    test('a co/pre group is advice, not a blocker', () {
      final status = PrerequisiteStatus.of(
        courseWith([
          [('CS F211', 'pre')],
          [('MATH F211', 'co/pre')],
        ]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
      expect(status.concurrent.single.label, 'MATH F211');
    });

    test('an unrecorded requirement type never declares you blocked', () {
      final status = PrerequisiteStatus.of(
        courseWith([
          [('CS F211', 'pre')],
          [('PHY F110', 'nan')],
        ]),
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
      expect(status.unclear.single.label, 'PHY F110');
    });

    group('cross-listed / alternative group (OR within a group)', () {
      test('cleared when any one option is passed', () {
        final status = PrerequisiteStatus.of(
          courseWith([
            [('ECE F211', 'pre'), ('EEE F211', 'pre'), ('INSTR F211', 'pre')],
          ]),
          // Student took it under the EEE code only.
          recordOf({'EEE F211': (grade: 'B', credits: 3)}),
        );
        expect(status.isMet, isTrue);
        expect(status.cleared.single.label, 'ECE F211 / EEE F211 / INSTR F211');
      });

      test('outstanding when none of the options is passed', () {
        final status = PrerequisiteStatus.of(
          courseWith([
            [('ECE F211', 'pre'), ('EEE F211', 'pre'), ('INSTR F211', 'pre')],
          ]),
          recordOf({'MATH F211': (grade: 'A', credits: 3)}),
        );
        expect(status.isMet, isFalse);
        expect(status.outstanding.single.options, hasLength(3));
      });
    });

    test('legacy slash-code + all_one convert to groups on read', () {
      // Old shape: one combined prereq, all_one unset → one group of OR options.
      final course = CoursePrerequisites.fromMap({
        'course_code': 'EEE F313',
        'has_prerequisites': true,
        'prereqs': [
          {'course_code': 'EEE/ECE F244', 'type': 'pre'},
        ],
      });
      expect(course.groups, hasLength(1));
      expect(course.groups.single.options.map((o) => o.courseCode),
          ['EEE F244', 'ECE F244']);

      final status = PrerequisiteStatus.of(
        course,
        recordOf({'ECE F244': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
    });

    test('legacy all_one="one" collapses the flat list into one OR group', () {
      final course = CoursePrerequisites.fromMap({
        'course_code': 'CS F320',
        'has_prerequisites': true,
        'all_one': 'one',
        'prereqs': [
          {'course_code': 'CS F211', 'type': 'pre'},
          {'course_code': 'CS F213', 'type': 'pre'},
        ],
      });
      expect(course.groups, hasLength(1));
      final status = PrerequisiteStatus.of(
        course,
        recordOf({'CS F211': (grade: 'A', credits: 3)}),
      );
      expect(status.isMet, isTrue);
    });

    test('co-requisite type aliases are canonicalised on read', () {
      // Whatever spelling the source used, the app only ever sees pre/co/pre/nan.
      for (final alias in ['co', 'co-req', 'coreq', 'pre/co', 'CO/PRE']) {
        final p = Prerequisite.fromMap({'course_code': 'X F211', 'type': alias});
        expect(p.type, 'co/pre', reason: '"$alias" should canonicalise to co/pre');
      }
      expect(Prerequisite.fromMap({'course_code': 'X', 'type': 'pre'}).type, 'pre');
      expect(Prerequisite.fromMap({'course_code': 'X', 'type': 'weird'}).type, 'nan');
    });

    test('round-trips through the new grouped map shape', () {
      final original = courseWith([
        [('ECE F211', 'pre'), ('EEE F211', 'pre')],
        [('MATH F211', 'co/pre')],
      ]);
      final restored = CoursePrerequisites.fromMap(original.toMap());
      expect(restored.groups, hasLength(2));
      expect(restored.groups.first.options.map((o) => o.courseCode), ['ECE F211', 'EEE F211']);
      expect(restored.groups.last.type, 'co/pre');
    });
  });
}
