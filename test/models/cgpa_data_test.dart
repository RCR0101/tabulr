import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/constants/app_constants.dart';
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
          _entry('CS F111', 4, 'A'),
          _entry('CS F222', 3, 'NC'),
        ],
      );
      // NC is a report, not a letter grade, so it contributes neither points
      // nor units (Academic Regulations 4.21) — only the 4-unit A counts.
      // This previously evaluated to 5.714 because the NC's units landed in the
      // denominator, which understated every affected student's SGPA and CGPA.
      expect(sem.sgpa, 10.0);
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

    test('cgpa dedup orders canonical semesters chronologically, not by map order', () {
      // Firestore returns documents sorted lexicographically by ID, which puts
      // 'ST 1' after '3-1' even though the summer term comes first. Build the
      // map in that (real) order and confirm the chronologically latest attempt
      // still wins.
      final data = CGPAData(semesters: {
        '3-1': SemesterData(
          semesterName: '3-1',
          courses: [_entry('CS F111', 4, 'A')], // true latest attempt
        ),
        'ST 1': SemesterData(
          semesterName: 'ST 1',
          courses: [_entry('CS F111', 4, 'C')], // earlier, but last in map
        ),
      });

      expect(data.cgpa, 10.0);
      expect(data.uniqueCourseCount, 1);
    });

    // Academic Regulations 4.21: the CGPA covers courses "in which He/she is
    // awarded letter grades", and where "merely a report emerges, this event by
    // itself will not alter the CGPA". NC is a report, not a letter grade.
    group('NC is a report, not a grade (clause 4.21)', () {
      test('an NC contributes neither grade points nor units', () {
        final sem = SemesterData(semesterName: '1-1', courses: [
          _entry('CS F111', 4, 'A'),
          _entry('BIO F110', 3, 'NC'),
        ]);

        // Only the 4-unit A counts — the NC's 3 units stay out of the divisor.
        expect(sem.totalCredits, 4.0);
        expect(sem.totalGradePoints, 40.0);
        expect(sem.sgpa, 10.0);
      });

      test('a course with only an NC is absent from the CGPA entirely', () {
        final data = CGPAData(semesters: {
          '1-1': SemesterData(
            semesterName: '1-1',
            courses: [_entry('BIO F110', 3, 'NC')],
          ),
        });

        expect(data.uniqueCourseCount, 0);
        expect(data.effectiveTotalCredits, 0.0);
        expect(data.cgpa, 0.0);
      });

      test('a later NC does not displace an earlier letter grade', () {
        final data = CGPAData(semesters: {
          '1-1': SemesterData(
            semesterName: '1-1',
            courses: [_entry('CS F111', 4, 'B')],
          ),
          '1-2': SemesterData(
            semesterName: '1-2',
            courses: [_entry('CS F111', 4, 'NC')],
          ),
        });

        // The B stands; the NC is merely a report.
        expect(data.cgpa, 8.0);
        expect(data.latestAttempts()['CS F111']!.entry.grade, 'B');
        expect(data.latestAttempts()['CS F111']!.semester, '1-1');
      });

      // Clause 4.17 (W) and 4.18-4.19 (RC): the report "will be ignored; this
      // means one should go backward to the previous performance, if any, which
      // takes over and this process must be repeated until one reaches a
      // performance which cannot be ignored". I and GA are transient (4.13,
      // 4.15) and behave the same until a real grade replaces them.
      for (final report in GradeConstants.reports) {
        test('a later $report falls back to the previous letter grade', () {
          final data = CGPAData(semesters: {
            '1-1': SemesterData(
              semesterName: '1-1',
              courses: [_entry('CS F111', 4, 'B')],
            ),
            '1-2': SemesterData(
              semesterName: '1-2',
              courses: [_entry('CS F111', 4, report)],
            ),
          });

          expect(data.cgpa, 8.0, reason: '$report must not displace the B');
          expect(data.latestAttempts()['CS F111']!.semester, '1-1');
        });

        test('$report contributes no units to a semester', () {
          final sem = SemesterData(semesterName: '1-1', courses: [
            _entry('CS F111', 4, 'A'),
            _entry('BIO F110', 3, report),
          ]);

          expect(sem.totalCredits, 4.0);
          expect(sem.sgpa, 10.0);
        });
      }

      test('consecutive reports keep falling back to the last real grade', () {
        final data = CGPAData(semesters: {
          '1-1': SemesterData(
            semesterName: '1-1',
            courses: [_entry('CS F111', 4, 'C')],
          ),
          '1-2': SemesterData(
            semesterName: '1-2',
            courses: [_entry('CS F111', 4, 'W')],
          ),
          '2-1': SemesterData(
            semesterName: '2-1',
            courses: [_entry('CS F111', 4, 'NC')],
          ),
        });

        // "repeated until one reaches a performance which cannot be ignored"
        expect(data.cgpa, 6.0);
        expect(data.latestAttempts()['CS F111']!.semester, '1-1');
      });

      test('a report is superseded once a real grade finally arrives', () {
        final data = CGPAData(semesters: {
          '1-1': SemesterData(
            semesterName: '1-1',
            courses: [_entry('CS F111', 4, 'GA')],
          ),
          '1-2': SemesterData(
            semesterName: '1-2',
            courses: [_entry('CS F111', 4, 'A')],
          ),
        });

        expect(data.cgpa, 10.0);
      });

      test('a later letter grade still replaces an earlier one', () {
        final data = CGPAData(semesters: {
          '1-1': SemesterData(
            semesterName: '1-1',
            courses: [_entry('CS F111', 4, 'E')],
          ),
          '1-2': SemesterData(
            semesterName: '1-2',
            courses: [_entry('CS F111', 4, 'A')],
          ),
        });

        expect(data.cgpa, 10.0);
      });
    });

    test('latestAttempts keeps one attempt per code and reports its semester', () {
      final data = CGPAData(semesters: {
        '1-1': SemesterData(
          semesterName: '1-1',
          courses: [_entry('CS F111', 4, 'E'), _entry('MATH F111', 3, 'B')],
        ),
        '1-2': SemesterData(
          semesterName: '1-2',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });

      final latest = data.latestAttempts();
      expect(latest.keys.toSet(), {'CS F111', 'MATH F111'});
      expect(latest['CS F111']!.entry.grade, 'A');
      expect(latest['CS F111']!.semester, '1-2');
      expect(latest['MATH F111']!.semester, '1-1');
    });

    test('latestAttempts can exclude a semester for prior-standing maths', () {
      final data = CGPAData(semesters: {
        '1-1': SemesterData(
          semesterName: '1-1',
          courses: [_entry('CS F111', 4, 'E')],
        ),
        '1-2': SemesterData(
          semesterName: '1-2',
          courses: [_entry('CS F111', 4, 'A')],
        ),
      });

      // Planning 1-2 means the standing before it still holds the 1-1 attempt.
      final prior = data.latestAttempts(excludingSemester: '1-2');
      expect(prior['CS F111']!.entry.grade, 'E');
      expect(prior['CS F111']!.semester, '1-1');
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
