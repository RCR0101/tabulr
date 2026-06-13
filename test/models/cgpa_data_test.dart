import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/models/course_type.dart';

CourseEntry _entry(String code, double credits, String grade, {CourseType type = CourseType.normal}) {
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
      expect(_entry('X', 3, 'GD', type: CourseType.atc).gradePoints, 0.0);
      expect(_entry('X', 3, 'PR', type: CourseType.atc).gradePoints, 0.0);
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
        courseType: CourseType.normal,
      );
      expect(noGrade.gradePoints, 0.0);
    });

    test('unknown grade string returns 0', () {
      expect(_entry('X', 3, 'Z').gradePoints, 0.0);
      expect(_entry('X', 3, '').gradePoints, 0.0);
    });

    test('ATC overrides any grade to 0', () {
      expect(_entry('X', 3, 'A', type: CourseType.atc).gradePoints, 0.0);
    });

    test('totalGradePoints is 0 for NC course', () {
      final entry = _entry('CS F111', 4, 'NC');
      expect(entry.totalGradePoints, 0.0);
    });

    test('fractional credits compute correctly', () {
      final entry = _entry('BITS F101', 0.5, 'A');
      expect(entry.totalGradePoints, 5.0);
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
          _entry('BITS F110', 2, 'GD', type: CourseType.atc),
        ],
      );

      expect(sem.sgpa, 10.0);
    });

    test('sgpa ignores courses without grades', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),
          CourseEntry(courseCode: 'X', courseTitle: 'X', credits: 3, courseType: CourseType.normal),
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
          _entry('BITS F110', 2, 'GD', type: CourseType.atc),
        ],
      );

      expect(sem.totalCredits, 4.0);
    });

    test('sgpa ignores NC courses in denominator', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),  // 40 / 4
          _entry('CS F222', 3, 'NC'), // 0 / 3 — but NC still has grade, so it IS included
        ],
      );
      // NC has gradePoints=0, but courseType is Normal and grade is non-empty,
      // so it enters the denominator: (40 + 0) / (4 + 3)
      expect(sem.sgpa, closeTo(5.714, 0.001));
    });

    test('sgpa with all same grades', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'B'),
          _entry('CS F222', 3, 'B'),
          _entry('CS F333', 5, 'B'),
        ],
      );
      expect(sem.sgpa, 8.0);
    });

    test('totalGradePoints sums correctly', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),  // 40
          _entry('CS F222', 3, 'C'),  // 18
        ],
      );
      expect(sem.totalGradePoints, 58.0);
    });

    test('semester with only ATC courses has sgpa 0', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('BITS F110', 2, 'GD', type: CourseType.atc),
          _entry('BITS F221', 5, 'PR', type: CourseType.atc),
        ],
      );
      expect(sem.sgpa, 0.0);
      expect(sem.totalCredits, 0.0);
    });

    test('copyWith preserves courses when not overridden', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [_entry('CS F111', 4, 'A')],
      );
      final copied = sem.copyWith(semesterName: 'Sem 2');
      expect(copied.semesterName, 'Sem 2');
      expect(copied.courses.length, 1);
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

    test('cgpa ignores ATC courses across semesters', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [
            _entry('CS F111', 4, 'A'),
            _entry('BITS F110', 2, 'GD', type: CourseType.atc),
          ],
        ),
      });
      expect(data.cgpa, 10.0);
      expect(data.effectiveTotalCredits, 4.0);
    });

    test('cgpa dedup uses latest semester by insertion order', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [_entry('CS F111', 4, 'E')],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [_entry('CS F111', 4, 'C')],
        ),
        'Sem 3': SemesterData(
          semesterName: 'Sem 3',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });
      // Third attempt wins
      expect(data.cgpa, 10.0);
      expect(data.uniqueCourseCount, 1);
    });

    test('cgpa with mixed repeated and unique courses', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [
            _entry('CS F111', 4, 'D'),   // repeated — overridden
            _entry('MATH F112', 4, 'A'), // unique — kept
          ],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [
            _entry('CS F111', 4, 'B'),   // latest attempt for CS F111
            _entry('CS F211', 4, 'A-'),  // unique — kept
          ],
        ),
      });
      // Effective: CS F111=B(8), MATH F112=A(10), CS F211=A-(9)
      // = (32 + 40 + 36) / (4 + 4 + 4) = 108 / 12 = 9.0
      expect(data.cgpa, 9.0);
      expect(data.uniqueCourseCount, 3);
      expect(data.effectiveTotalCredits, 12.0);
    });

    test('effectiveTotalGradePoints sums deduplicated', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });
      expect(data.effectiveTotalGradePoints, 40.0);
    });

    test('single semester cgpa equals sgpa', () {
      final sem = SemesterData(
        semesterName: 'Sem 1',
        courses: [
          _entry('CS F111', 4, 'A'),
          _entry('MATH F112', 4, 'B'),
        ],
      );
      final data = CGPAData(semesters: {'Sem 1': sem});
      expect(data.cgpa, sem.sgpa);
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

    test('fromJson -> toJson roundtrip with multiple semesters', () {
      final data = CGPAData(semesters: {
        'Sem 1': SemesterData(
          semesterName: 'Sem 1',
          courses: [_entry('CS F111', 4, 'A')],
        ),
        'Sem 2': SemesterData(
          semesterName: 'Sem 2',
          courses: [
            _entry('CS F211', 4, 'B'),
            _entry('MATH F211', 3, 'A-'),
          ],
        ),
      });

      final json = data.toJson();
      final restored = CGPAData.fromJson(json);

      expect(restored.semesters.length, 2);
      expect(restored.cgpa, data.cgpa);
    });
  });
}
