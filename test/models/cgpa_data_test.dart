import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/cgpa_data.dart';

CourseEntry _entry(String code, double credits, String grade, {String type = 'Normal'}) {
  return CourseEntry(
    courseCode: code,
    courseTitle: code,
    credits: credits,
    courseType: type,
    grade: grade,
  );
}

void main() {
  group('CourseEntry', () {
    test('gradePoints maps all normal grades correctly', () {
      expect(_entry('X', 3, 'A').gradePoints, 10.0);
      expect(_entry('X', 3, 'A-').gradePoints, 9.0);
      expect(_entry('X', 3, 'B').gradePoints, 8.0);
      expect(_entry('X', 3, 'B-').gradePoints, 7.0);
      expect(_entry('X', 3, 'C').gradePoints, 6.0);
      expect(_entry('X', 3, 'C-').gradePoints, 5.0);
      expect(_entry('X', 3, 'D').gradePoints, 4.0);
      expect(_entry('X', 3, 'D-').gradePoints, 3.0);
      expect(_entry('X', 3, 'E').gradePoints, 2.0);
      expect(_entry('X', 3, 'NC').gradePoints, 0.0);
    });

    test('ATC courses always return 0 grade points', () {
      expect(_entry('X', 3, 'GD', type: 'ATC').gradePoints, 0.0);
      expect(_entry('X', 3, 'PR', type: 'ATC').gradePoints, 0.0);
    });

    test('totalGradePoints = credits * gradePoints', () {
      final entry = _entry('CS F111', 4, 'A');
      expect(entry.totalGradePoints, 40.0);
    });

    test('fromJson -> toJson roundtrip', () {
      final entry = _entry('CS F111', 4, 'A');
      final json = entry.toJson();
      final restored = CourseEntry.fromJson(json);

      expect(restored.courseCode, 'CS F111');
      expect(restored.credits, 4.0);
      expect(restored.grade, 'A');
    });

    test('copyWith overrides specified fields only', () {
      final entry = _entry('CS F111', 4, 'A');
      final copied = entry.copyWith(grade: 'B');

      expect(copied.grade, 'B');
      expect(copied.courseCode, 'CS F111');
      expect(copied.credits, 4);
    });

    test('null/unknown grade returns 0', () {
      final noGrade = CourseEntry(
        courseCode: 'X',
        courseTitle: 'X',
        credits: 3,
        courseType: 'Normal',
      );
      expect(noGrade.gradePoints, 0.0);
    });
  });

  group('SemesterData', () {
    test('sgpa calculated correctly for single semester', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),   // 40 grade points
          _entry('MATH F112', 4, 'B'), // 32 grade points
        ],
      );

      // SGPA = (40 + 32) / (4 + 4) = 72 / 8 = 9.0
      expect(sem.sgpa, 9.0);
    });

    test('sgpa ignores ATC courses', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),
          _entry('BITS F110', 2, 'GD', type: 'ATC'),
        ],
      );

      expect(sem.sgpa, 10.0);
    });

    test('sgpa ignores courses without grades', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),
          CourseEntry(courseCode: 'X', courseTitle: 'X', credits: 3, courseType: 'Normal'),
        ],
      );

      expect(sem.sgpa, 10.0);
    });

    test('sgpa returns 0 for empty semester', () {
      final sem = SemesterData(semesterName: 'Sem 1');
      expect(sem.sgpa, 0.0);
    });

    test('totalCredits counts only normal graded courses', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),
          _entry('BITS F110', 2, 'GD', type: 'ATC'),
        ],
      );

      expect(sem.totalCredits, 4.0);
    });

    test('fromJson -> toJson roundtrip', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [_entry('CS F111', 4, 'A')],
      );

      final json = sem.toJson();
      final restored = SemesterData.fromJson(json);

      expect(restored.semesterName, 'Sem 1');
      expect(restored.courses.length, 1);
      expect(restored.courses.first.courseCode, 'CS F111');
    });
  });

  group('CGPAData', () {
    test('cgpa calculated across multiple semesters', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [
            _entry('CS F111', 4, 'A'),   // 40
            _entry('MATH F112', 4, 'B'), // 32
          ],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [
            _entry('CS F211', 4, 'A-'),  // 36
            _entry('MATH F211', 4, 'A'), // 40
          ],
        ),
      });

      // CGPA = (40 + 32 + 36 + 40) / (4 + 4 + 4 + 4) = 148 / 16 = 9.25
      expect(data.cgpa, 9.25);
    });

    test('cgpa deduplicates repeated courses keeping latest attempt', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [
            _entry('CS F111', 4, 'D'), // First attempt — should be overridden
          ],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [
            _entry('CS F111', 4, 'A'), // Second attempt — this one counts
          ],
        ),
      });

      // Only the A grade counts: 40 / 4 = 10.0
      expect(data.cgpa, 10.0);
    });

    test('cgpa returns 0 for empty data', () {
      final data = CGPAData();
      expect(data.cgpa, 0.0);
    });

    test('effectiveTotalCredits uses deduplicated courses', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [_entry('CS F111', 4, 'D')],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });

      expect(data.effectiveTotalCredits, 4.0);
    });

    test('fromJson -> toJson roundtrip', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });

      final json = data.toJson();
      final restored = CGPAData.fromJson(json);

      expect(restored.semesters.length, 1);
      expect(restored.semesters['Sem 1']!.courses.first.grade, 'A');
    });
  });
}
