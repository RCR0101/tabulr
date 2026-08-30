import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timetable_maker/services/core/cgpa_calculator_controller.dart';
import 'package:timetable_maker/services/data/cgpa_service.dart';
import 'package:timetable_maker/models/all_course.dart';
import 'package:timetable_maker/models/cgpa_data.dart';

class MockCGPAService extends Mock implements CGPAService {}

void main() {
  group('CGPACalculatorController', () {
    late CGPACalculatorController controller;

    setUp(() {
      controller = CGPACalculatorController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('semester management', () {
      test('addSemester adds new semester', () {
        expect(controller.addSemester('1-1'), isTrue);
        expect(controller.semesters, contains('1-1'));
      });

      test('addSemester rejects empty name', () {
        expect(controller.addSemester(''), isFalse);
      });

      test('addSemester rejects duplicate', () {
        controller.addSemester('1-1');
        expect(controller.addSemester('1-1'), isFalse);
      });

      test('nextNormalSemester starts at 1-1 when empty', () {
        expect(controller.nextNormalSemester(), '1-1');
      });

      test('nextNormalSemester increments correctly', () {
        controller.addSemester('1-1');
        expect(controller.nextNormalSemester(), '1-2');

        controller.addSemester('1-2');
        expect(controller.nextNormalSemester(), '2-1');

        controller.addSemester('2-1');
        expect(controller.nextNormalSemester(), '2-2');
      });

      test('nextSummerTerm increments correctly', () {
        expect(controller.nextSummerTerm(), 'ST 1');
        controller.addSemester('ST 1');
        expect(controller.nextSummerTerm(), 'ST 2');
      });

      // The progression is fixed, so a hole in it is unambiguous. Offering
      // max + 1 instead left a deleted semester with no way back.
      test('a deleted semester is what gets offered next', () async {
        final mock = MockCGPAService();
        when(() => mock.deleteSemesterData(any())).thenAnswer((_) async => true);
        final c = CGPACalculatorController(cgpaService: mock);
        addTearDown(c.dispose);

        for (final s in ['1-1', '1-2', '2-1', '2-2']) {
          c.addSemester(s);
        }
        expect(c.nextNormalSemester(), '3-1');

        await c.removeSemester('1-2');
        expect(c.nextNormalSemester(), '1-2');
      });

      test('a deleted summer term is what gets offered next', () async {
        final mock = MockCGPAService();
        when(() => mock.deleteSemesterData(any())).thenAnswer((_) async => true);
        final c = CGPACalculatorController(cgpaService: mock);
        addTearDown(c.dispose);

        c.addSemester('ST 1');
        c.addSemester('ST 2');
        await c.removeSemester('ST 1');
        // ST 2 without ST 1 isn't a state the progression allows — repair it
        // rather than offering ST 3 on top.
        expect(c.nextSummerTerm(), 'ST 1');
      });

      test('a re-added semester lands in order, not at the end', () {
        for (final s in ['1-1', '1-2', '2-1', 'ST 1', '3-1']) {
          controller.addSemester(s);
        }
        controller.addSemester('2-2');
        expect(controller.semesters, ['1-1', '1-2', '2-1', '2-2', 'ST 1', '3-1']);
      });

      test('an unrecognised semester name still sorts last', () {
        controller.addSemester('2-1');
        controller.addSemester('Exchange term');
        controller.addSemester('1-1');
        expect(controller.semesters, ['1-1', '2-1', 'Exchange term']);
      });
    });

    group('course operations', () {
      test('addCourseToSemester adds course', () {
        controller.addSemester('1-1');
        final course = AllCourse(
          courseCode: 'CS F111',
          courseTitle: 'Computer Programming',
          creditValue: 4,
          type: 'Normal',
        );

        expect(controller.addCourseToSemester('1-1', course),
            AddCourseResult.added);
        expect(controller.cgpaData.semesters['1-1']!.courses.length, 1);
        expect(controller.cgpaData.semesters['1-1']!.courses[0].courseCode, 'CS F111');
      });

      test('addCourseToSemester rejects duplicate', () {
        controller.addSemester('1-1');
        final course = AllCourse(
          courseCode: 'CS F111',
          courseTitle: 'Computer Programming',
          creditValue: 4,
          type: 'Normal',
        );

        controller.addCourseToSemester('1-1', course);
        expect(controller.addCourseToSemester('1-1', course),
            AddCourseResult.duplicate);
      });

      test('a record counts one way: credits or credit hours, never both', () {
        controller.addSemester('1-1');
        expect(
          controller.addCourseToSemester(
              '1-1',
              AllCourse(
                courseCode: 'CS F211',
                courseTitle: 'Data Structures',
                creditValue: 4,
                type: 'Normal',
              )),
          AddCourseResult.added,
        );

        // Pilani's CHEM U101: 7 contact hours, no published unit count. Nobody
        // registers for both kinds, so this cannot join the record.
        expect(
          controller.addCourseToSemester(
              '1-1',
              AllCourse(
                courseCode: 'CHEM U101',
                courseTitle: 'Atomic Structure',
                creditValue: 0,
                creditHours: 7,
                type: 'Normal',
              )),
          AddCourseResult.basisMismatch,
        );
        expect(controller.cgpaData.semesters['1-1']!.courses.length, 1);
      });

      test('the check spans the record, not just one semester', () {
        controller.addSemester('1-1');
        controller.addSemester('1-2');
        controller.addCourseToSemester(
            '1-1',
            AllCourse(
              courseCode: 'CHEM U101',
              courseTitle: 'Atomic Structure',
              creditValue: 0,
              creditHours: 7,
              type: 'Normal',
            ));

        expect(
          controller.addCourseToSemester(
              '1-2',
              AllCourse(
                courseCode: 'CS F211',
                courseTitle: 'Data Structures',
                creditValue: 4,
                type: 'Normal',
              )),
          AddCourseResult.basisMismatch,
        );
      });

      test('removeCourseFromSemester removes course', () {
        controller.addSemester('1-1');
        final course = AllCourse(
          courseCode: 'CS F111',
          courseTitle: 'Computer Programming',
          creditValue: 4,
          type: 'Normal',
        );

        controller.addCourseToSemester('1-1', course);
        controller.removeCourseFromSemester('1-1', 0);
        expect(controller.cgpaData.semesters['1-1']!.courses, isEmpty);
      });

      test('updateGrade updates course grade', () {
        controller.addSemester('1-1');
        final course = AllCourse(
          courseCode: 'CS F111',
          courseTitle: 'Computer Programming',
          creditValue: 4,
          type: 'Normal',
        );

        controller.addCourseToSemester('1-1', course);
        controller.updateGrade('1-1', 0, 'A');
        expect(controller.cgpaData.semesters['1-1']!.courses[0].grade, 'A');
      });
    });

    group('calculations', () {
      test('cumulativeCgpa computes correctly', () {
        controller.addSemester('1-1');
        controller.addSemester('1-2');

        final c1 = AllCourse(courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal');
        final c2 = AllCourse(courseCode: 'MATH F111', courseTitle: 'Math I', creditValue: 4, type: 'Normal');

        controller.addCourseToSemester('1-1', c1);
        controller.updateGrade('1-1', 0, 'A'); // 10 points

        controller.addCourseToSemester('1-2', c2);
        controller.updateGrade('1-2', 0, 'B'); // 8 points

        // Cumulative up to 1-1: 10.0
        expect(controller.cumulativeCgpa('1-1'), 10.0);

        // Cumulative up to 1-2: (10*4 + 8*4) / 8 = 9.0
        expect(controller.cumulativeCgpa('1-2'), 9.0);
      });

      test('isSuperseded detects repeated course', () {
        controller.addSemester('1-1');
        controller.addSemester('1-2');

        final c1 = AllCourse(courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal');

        controller.addCourseToSemester('1-1', c1);
        controller.addCourseToSemester('1-2', c1);
        controller.updateGrade('1-1', 0, 'D');
        controller.updateGrade('1-2', 0, 'A');

        expect(controller.isSuperseded('1-1', 'CS F111'), isTrue);
        expect(controller.isSuperseded('1-2', 'CS F111'), isFalse);
      });

      test('a pending repeat does not supersede the earlier grade', () {
        controller.addSemester('3-2');
        controller.addSemester('ST 2');

        final course = AllCourse(
          courseCode: 'CS F111',
          courseTitle: 'CP',
          creditValue: 4,
          type: 'Normal',
        );

        controller.addCourseToSemester('3-2', course);
        controller.updateGrade('3-2', 0, 'D');
        controller.addCourseToSemester('ST 2', course);

        expect(controller.isSuperseded('3-2', 'CS F111'), isFalse);
      });
    });

    group('import', () {
      test('importCoursesFromTimetable adds courses', () {
        controller.addSemester('1-1');
        final courses = [
          AllCourse(courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal'),
          AllCourse(courseCode: 'MATH F111', courseTitle: 'Math I', creditValue: 4, type: 'Normal'),
        ];

        final count = controller.importCoursesFromTimetable({'1-1': courses});
        expect(count, 2);
        expect(controller.cgpaData.semesters['1-1']!.courses.length, 2);
      });

      test('importCoursesFromTimetable creates new semester if needed', () {
        final courses = [
          AllCourse(courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal'),
        ];

        controller.importCoursesFromTimetable({'2-1': courses});
        expect(controller.semesters, contains('2-1'));
      });
    });

    group('getGradeDescription', () {
      test('returns correct descriptions', () {
        expect(CGPACalculatorController.getGradeDescription('A'), '10 Grade Points');
        expect(CGPACalculatorController.getGradeDescription('B'), '8 Grade Points');
        expect(CGPACalculatorController.getGradeDescription('GD'), 'Good');
        expect(CGPACalculatorController.getGradeDescription('NC'), 'Not Cleared');
        expect(CGPACalculatorController.getGradeDescription('X'), '');
      });
    });

    group('notifyListeners', () {
      test('addCourseToSemester notifies', () {
        controller.addSemester('1-1');
        int callCount = 0;
        controller.addListener(() => callCount++);

        controller.addCourseToSemester('1-1', AllCourse(
          courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal',
        ));
        expect(callCount, 1);
      });

      test('updateGrade notifies', () {
        controller.addSemester('1-1');
        controller.addCourseToSemester('1-1', AllCourse(
          courseCode: 'CS F111', courseTitle: 'CP', creditValue: 4, type: 'Normal',
        ));

        int callCount = 0;
        controller.addListener(() => callCount++);
        controller.updateGrade('1-1', 0, 'A');
        expect(callCount, 1);
      });
    });

    group('saveSemester', () {
      setUpAll(() {
        registerFallbackValue(SemesterData(semesterName: 'fallback'));
      });

      AllCourse sampleCourse() => AllCourse(
            courseCode: 'CS F111',
            courseTitle: 'Computer Programming',
            creditValue: 4,
            type: 'Normal',
          );

      test('returns nothingToSave for an unknown semester', () async {
        final c = CGPACalculatorController();
        expect(await c.saveSemester('does-not-exist'),
            SemesterSaveResult.nothingToSave);
        c.dispose();
      });

      test('returns saved when the service write succeeds', () async {
        final mock = MockCGPAService();
        when(() => mock.saveSemesterData(any(), any()))
            .thenAnswer((_) async => true);
        final c = CGPACalculatorController(cgpaService: mock);
        c.addSemester('1-1');
        c.addCourseToSemester('1-1', sampleCourse());

        expect(await c.saveSemester('1-1'), SemesterSaveResult.saved);
        c.dispose();
      });

      test('returns failed when the service write fails', () async {
        final mock = MockCGPAService();
        when(() => mock.saveSemesterData(any(), any()))
            .thenAnswer((_) async => false);
        final c = CGPACalculatorController(cgpaService: mock);
        c.addSemester('1-1');
        c.addCourseToSemester('1-1', sampleCourse());

        expect(await c.saveSemester('1-1'), SemesterSaveResult.failed);
        c.dispose();
      });
    });
  });
}
