import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/core/cgpa_calculator_controller.dart';
import 'package:timetable_maker/models/all_course.dart';

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

        expect(controller.addCourseToSemester('1-1', course), isTrue);
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
        expect(controller.addCourseToSemester('1-1', course), isFalse);
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

        expect(controller.isSuperseded('1-1', 'CS F111'), isTrue);
        expect(controller.isSuperseded('1-2', 'CS F111'), isFalse);
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
  });
}
