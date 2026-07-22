import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/models/course_type.dart';

AcademicRecord recordOf(Map<String, ({String grade, double credits})> courses) {
  final attempts = <String, CourseAttempt>{};
  courses.forEach((code, info) {
    attempts[AcademicRecord.normalizeCode(code)] = (
      semester: '2-1',
      entry: CourseEntry(
        courseCode: code,
        courseTitle: code,
        credits: info.credits,
        courseType: CourseType.normal,
        grade: info.grade,
      ),
    );
  });
  return AcademicRecord(attempts: attempts, cgpa: 0);
}

void main() {
  group('normalizeCode', () {
    test('strips the spacing that differs between sources', () {
      // The Bulletin writes "CS F320"; a pasted performance sheet may not.
      expect(AcademicRecord.normalizeCode('CS F320'),
          AcademicRecord.normalizeCode('CSF320'));
      expect(AcademicRecord.normalizeCode('cs  f320'),
          AcademicRecord.normalizeCode('CS F320'));
    });
  });

  group('AcademicRecord', () {
    test('an empty record answers no to everything', () {
      expect(AcademicRecord.empty.isEmpty, isTrue);
      expect(AcademicRecord.empty.hasPassed('CS F111'), isFalse);
      expect(AcademicRecord.empty.hasFailed('CS F111'), isFalse);
      expect(AcademicRecord.empty.gradeFor('CS F111'), isNull);
    });

    test('finds a course however its code is spaced', () {
      final record = recordOf({'CS F320': (grade: 'A', credits: 3)});
      expect(record.hasPassed('CSF320'), isTrue);
      expect(record.gradeFor('cs f320'), 'A');
    });

    test('E counts as attempted, not cleared', () {
      final record = recordOf({'CS F111': (grade: 'E', credits: 4)});
      expect(record.hasPassed('CS F111'), isFalse);
      expect(record.hasFailed('CS F111'), isTrue);
    });

    test('every other letter grade clears, including D-', () {
      // D- is absent from the 2023 regulations but does exist in practice.
      final record = recordOf({'CS F111': (grade: 'D-', credits: 4)});
      expect(record.hasPassed('CS F111'), isTrue);
    });

    test('cgpaAcross weights by credits and ignores untaken courses', () {
      final record = recordOf({
        'CS F320': (grade: 'A', credits: 3), // 10 * 3 = 30
        'CS F211': (grade: 'B', credits: 4), // 8 * 4 = 32
      });
      // 62 / 7
      expect(record.cgpaAcross(['CS F320', 'CS F211', 'CS F999']),
          closeTo(8.857, 0.001));
    });

    test('cgpaAcross is null rather than zero when nothing is graded', () {
      // A real 0.0 would wrongly read as "below the 4.50 a minor needs".
      final record = recordOf({'CS F320': (grade: 'A', credits: 3)});
      expect(record.cgpaAcross(['MATH F211']), isNull);
      expect(AcademicRecord.empty.cgpaAcross(['CS F320']), isNull);
    });
  });
}
