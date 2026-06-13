import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/all_course.dart';
import 'package:timetable_maker/models/course_type.dart';
import 'package:timetable_maker/services/parsers/performance_sheet_parser.dart';

AllCourse _course(String code, String title, double credits) {
  return AllCourse(
    courseCode: code,
    courseTitle: title,
    creditValue: credits,
    type: 'Normal',
  );
}

ParsedPerformanceSheet _sheet(List<ParsedSemester> semesters) {
  return ParsedPerformanceSheet(semesters: semesters);
}

ParsedSemester _semester(String name, List<ParsedCourseEntry> courses) {
  return ParsedSemester(rawName: name, normalizedName: name, courses: courses);
}

ParsedCourseEntry _entry(String code, String grade, {String? tag}) {
  return ParsedCourseEntry(courseCode: code, grade: grade, tag: tag);
}

void main() {
  group('extractCoursesFromChunk', () {
    test('extracts two courses with codes, titles, units, and grades', () {
      final chunk =
          'BIO F101 INTRODUCTION TO BIOLOGICAL SCI 3.0 CS F111 COMPUTER PROGRAMMING 4.0 A B';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 2);
      expect(results[0].courseCode, 'BIO F101');
      expect(results[0].grade, 'A');
      expect(results[1].courseCode, 'CS F111');
      expect(results[1].grade, 'B');
    });

    test('extracts single course', () {
      final chunk = 'CS F111 COMPUTER PROGRAMMING 4.0 A';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].courseCode, 'CS F111');
      expect(results[0].grade, 'A');
    });

    test('extracts courses with tags', () {
      final chunk =
          'ECON F211 PRINCIPLES OF ECONOMICS 3.0 BITS F312 PRACTICE SCHOOL I 6.0 A HEL GD';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 2);
      expect(results[0].courseCode, 'ECON F211');
      expect(results[0].grade, 'A');
      expect(results[0].tag, 'HEL');
      expect(results[1].courseCode, 'BITS F312');
      expect(results[1].grade, 'GD');
      expect(results[1].tag, isNull);
    });

    test('extracts courses with DEL tag', () {
      final chunk = 'CS F211 DATA STRUCTURES 4.0 B DEL';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].courseCode, 'CS F211');
      expect(results[0].grade, 'B');
      expect(results[0].tag, 'DEL');
    });

    test('extracts courses with EL tag', () {
      final chunk = 'HSS F234 SOCIOLOGY 3.0 A- EL';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].grade, 'A-');
      expect(results[0].tag, 'EL');
    });

    test('handles K-prefix course codes', () {
      final chunk = 'BITS K101 PHYSICAL EDUCATION 0.5 A';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].courseCode, 'BITS K101');
      expect(results[0].grade, 'A');
    });

    test('handles hyphenated course codes', () {
      final chunk =
          'BITS F101-1 THERMODYNAMICS 3.0 BITS F101-2 MECHANICS 3.0 A B';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 2);
      expect(results[0].courseCode, 'BITS F101-1');
      expect(results[1].courseCode, 'BITS F101-2');
    });

    test('returns empty for chunk with no course codes', () {
      final chunk = 'SOME RANDOM TEXT WITHOUT COURSE CODES 3.0 A';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results, isEmpty);
    });

    test('returns empty for empty chunk', () {
      final results = PerformanceSheetParser.extractCoursesFromChunk('');

      expect(results, isEmpty);
    });

    test('pairs only courses that have matching grades', () {
      final chunk =
          'CS F111 COMP PROG 4.0 MATH F112 MATHEMATICS I 3.0 PHY F111 PHYSICS 3.0 A B';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 2);
      expect(results[0].courseCode, 'CS F111');
      expect(results[0].grade, 'A');
      expect(results[1].courseCode, 'MATH F112');
      expect(results[1].grade, 'B');
    });

    test('handles float units without confusing them with grades', () {
      final chunk = 'BITS K101 PHYED 0.5 A';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].grade, 'A');
    });

    test('handles minus grades correctly', () {
      final chunk = 'CS F111 COMP PROG 4.0 A-';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].grade, 'A-');
    });

    test('handles NC grade', () {
      final chunk = 'CS F111 COMP PROG 4.0 NC';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].grade, 'NC');
    });

    test('handles GD and PR grades', () {
      final chunk = 'BITS F312 PS I 6.0 BITS F411 PS II 6.0 GD PR';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 2);
      expect(results[0].grade, 'GD');
      expect(results[1].grade, 'PR');
    });

    test('handles G-prefix course codes', () {
      final chunk = 'CS G513 NETWORK PROGRAMMING 3.0 A';
      final results = PerformanceSheetParser.extractCoursesFromChunk(chunk);

      expect(results.length, 1);
      expect(results[0].courseCode, 'CS G513');
    });
  });

  group('normalizeSemesterName', () {
    test('first semester maps to year-1', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'FIRST SEMESTER 2025-2026',
        ['2025-2026'],
        0,
      );

      expect(result, '1-1');
    });

    test('second semester maps to year-2', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'SECOND SEMESTER 2025-2026',
        ['2025-2026'],
        0,
      );

      expect(result, '1-2');
    });

    test('second academic year increments year number', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'FIRST SEMESTER 2026-2027',
        ['2025-2026', '2026-2027'],
        0,
      );

      expect(result, '2-1');
    });

    test('summer term uses counter', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'SUMMER TERM 2025-2026',
        ['2025-2026'],
        0,
      );

      expect(result, 'ST 1');
    });

    test('second summer term increments counter', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'SUMMER TERM 2026-2027',
        ['2025-2026', '2026-2027'],
        1,
      );

      expect(result, 'ST 2');
    });

    test('unknown year defaults to year 1', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'FIRST SEMESTER 2030-2031',
        ['2025-2026'],
        0,
      );

      expect(result, '1-1');
    });

    test('unrecognized format returns raw name', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'SOME OTHER FORMAT',
        ['2025-2026'],
        0,
      );

      expect(result, 'SOME OTHER FORMAT');
    });

    test('case insensitive matching', () {
      final result = PerformanceSheetParser.normalizeSemesterName(
        'First Semester 2025-2026',
        ['2025-2026'],
        0,
      );

      expect(result, '1-1');
    });
  });

  group('toCGPAData', () {
    test('converts parsed courses with catalog lookup', () {
      final parsed = _sheet([
        _semester('1-1', [
          _entry('CS F111', 'A'),
          _entry('MATH F112', 'B'),
        ]),
      ]);
      final catalog = [
        _course('CS F111', 'Computer Programming', 4.0),
        _course('MATH F112', 'Mathematics I', 3.0),
      ];

      final result = PerformanceSheetParser.toCGPAData(parsed, catalog);

      expect(result.semesters.length, 1);
      final sem = result.semesters['1-1']!;
      expect(sem.courses.length, 2);
      expect(sem.courses[0].courseTitle, 'Computer Programming');
      expect(sem.courses[0].credits, 4.0);
      expect(sem.courses[0].grade, 'A');
      expect(sem.courses[1].courseTitle, 'Mathematics I');
      expect(sem.courses[1].credits, 3.0);
    });

    test('GD grade produces ATC course type', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('BITS F312', 'GD')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters['1-1']!.courses[0].courseType, CourseType.atc);
    });

    test('PR grade produces ATC course type', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('BITS F411', 'PR')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters['1-1']!.courses[0].courseType, CourseType.atc);
    });

    test('normal grades produce Normal course type', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('CS F111', 'A')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters['1-1']!.courses[0].courseType, CourseType.normal);
    });

    test('defaults to 3.0 credits when course not in catalog', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('CS F999', 'A')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters['1-1']!.courses[0].credits, 3.0);
    });

    test('defaults to course code as title when not in catalog', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('CS F999', 'A')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters['1-1']!.courses[0].courseTitle, 'CS F999');
    });

    test('case-insensitive course code lookup', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('cs f111', 'A')]),
      ]);
      final catalog = [_course('CS F111', 'Computer Programming', 4.0)];

      final result = PerformanceSheetParser.toCGPAData(parsed, catalog);

      expect(result.semesters['1-1']!.courses[0].courseTitle, 'Computer Programming');
      expect(result.semesters['1-1']!.courses[0].credits, 4.0);
    });

    test('multiple semesters produce separate entries', () {
      final parsed = _sheet([
        _semester('1-1', [_entry('CS F111', 'A')]),
        _semester('1-2', [_entry('CS F211', 'B')]),
      ]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters.length, 2);
      expect(result.semesters.containsKey('1-1'), isTrue);
      expect(result.semesters.containsKey('1-2'), isTrue);
    });

    test('empty parsed sheet produces empty CGPAData', () {
      final parsed = _sheet([]);

      final result = PerformanceSheetParser.toCGPAData(parsed, []);

      expect(result.semesters, isEmpty);
    });
  });

  group('parse', () {
    test('non-PDF bytes returns warning', () async {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04]);

      final result = await PerformanceSheetParser.parse(bytes);

      expect(result.semesters, isEmpty);
      expect(result.warnings, contains('File is not a valid PDF'));
    });

    test('empty bytes returns warning', () async {
      final bytes = Uint8List(0);

      final result = await PerformanceSheetParser.parse(bytes);

      expect(result.semesters, isEmpty);
      expect(result.warnings, contains('File is not a valid PDF'));
    });

    test('bytes shorter than 4 returns warning', () async {
      final bytes = Uint8List.fromList([0x25, 0x50]);

      final result = await PerformanceSheetParser.parse(bytes);

      expect(result.semesters, isEmpty);
      expect(result.warnings, contains('File is not a valid PDF'));
    });
  });

  group('ParsedPerformanceSheet', () {
    test('totalCourses sums across semesters', () {
      final sheet = _sheet([
        _semester('1-1', [_entry('CS F111', 'A'), _entry('CS F211', 'B')]),
        _semester('1-2', [_entry('CS F311', 'C')]),
      ]);

      expect(sheet.totalCourses, 3);
    });

    test('totalCourses is 0 for empty sheet', () {
      final sheet = _sheet([]);

      expect(sheet.totalCourses, 0);
    });
  });

  group('ParsedCourseEntry', () {
    test('toString without tag', () {
      final entry = _entry('CS F111', 'A');
      expect(entry.toString(), 'CS F111: A');
    });

    test('toString with tag', () {
      final entry = _entry('CS F111', 'A', tag: 'HEL');
      expect(entry.toString(), 'CS F111: A (HEL)');
    });
  });

  group('ParsedSemester', () {
    test('toString shows course count', () {
      final semester = _semester('1-1', [_entry('CS F111', 'A')]);
      expect(semester.toString(), '1-1: 1 courses');
    });
  });
}
