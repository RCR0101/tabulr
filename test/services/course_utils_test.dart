import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/services/core/course_utils.dart';
import '../helpers/test_data.dart';

void main() {
  late List<Course> courses;

  setUp(() {
    courses = [
      makeCourse(
        courseCode: 'CS F111',
        courseTitle: 'Computer Programming',
        lectureCredits: 3,
        practicalCredits: 1,
        sections: [
          makeSection(sectionId: 'L1', instructor: 'SAYAN DAS', days: [DayOfWeek.M, DayOfWeek.W], hours: [1]),
          makeSection(sectionId: 'L2', instructor: 'KAVI DEVRAJ', days: [DayOfWeek.T, DayOfWeek.Th], hours: [2]),
          makeSection(sectionId: 'P1', type: SectionType.P, instructor: 'Lab Staff', days: [DayOfWeek.F], hours: [7, 8]),
        ],
        midSemExam: makeExam(date: DateTime(2026, 3, 10)),
      ),
      makeCourse(
        courseCode: 'MATH F112',
        courseTitle: 'Mathematics I',
        lectureCredits: 3,
        practicalCredits: 0,
        sections: [
          makeSection(sectionId: 'L1', instructor: 'PROF SHARMA', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [3]),
        ],
        midSemExam: makeExam(date: DateTime(2026, 3, 11)),
      ),
      makeCourse(
        courseCode: 'BIO F111',
        courseTitle: 'General Biology',
        lectureCredits: 2,
        practicalCredits: 1,
        sections: [
          makeSection(sectionId: 'L1', instructor: 'Dr. Smith', days: [DayOfWeek.T], hours: [4]),
        ],
      ),
    ];
  });

  group('getInstructorInCharge', () {
    test('returns all-caps instructor name', () {
      final ic = CourseUtils.getInstructorInCharge(courses[0]);
      expect(ic, 'SAYAN DAS');
    });

    test('returns Unknown for course with no sections', () {
      final emptyCourse = makeCourse(courseCode: 'EMPTY', sections: []);
      expect(CourseUtils.getInstructorInCharge(emptyCourse), 'Unknown');
    });
  });

  group('searchCourses', () {
    test('empty query returns all courses', () {
      expect(CourseUtils.searchCourses(courses, ''), courses);
    });

    test('matches by course code', () {
      final results = CourseUtils.searchCourses(courses, 'CS F111');
      expect(results.length, 1);
      expect(results.first.courseCode, 'CS F111');
    });

    test('matches by course title', () {
      final results = CourseUtils.searchCourses(courses, 'biology');
      expect(results.length, 1);
      expect(results.first.courseCode, 'BIO F111');
    });

    test('matches by instructor name', () {
      final results = CourseUtils.searchCourses(courses, 'sayan');
      expect(results.length, 1);
      expect(results.first.courseCode, 'CS F111');
    });

    test('case insensitive', () {
      expect(CourseUtils.searchCourses(courses, 'MATH').length, 1);
      expect(CourseUtils.searchCourses(courses, 'math').length, 1);
    });
  });

  group('filterByInstructor', () {
    test('empty string returns all', () {
      expect(CourseUtils.filterByInstructor(courses, '').length, courses.length);
    });

    test('filters by instructor substring', () {
      final results = CourseUtils.filterByInstructor(courses, 'sharma');
      expect(results.length, 1);
      expect(results.first.courseCode, 'MATH F112');
    });
  });

  group('filterByCourseCode', () {
    test('filters by partial code', () {
      final results = CourseUtils.filterByCourseCode(courses, 'F111');
      expect(results.length, 2); // CS F111 and BIO F111
    });
  });

  group('filterByExamDate', () {
    test('returns courses with matching mid-sem date', () {
      final results = CourseUtils.filterByExamDate(courses, DateTime(2026, 3, 10), true);
      expect(results.length, 1);
      expect(results.first.courseCode, 'CS F111');
    });

    test('null date returns all', () {
      expect(CourseUtils.filterByExamDate(courses, null, true).length, courses.length);
    });

    test('returns empty when no match', () {
      final results = CourseUtils.filterByExamDate(courses, DateTime(2099, 1, 1), true);
      expect(results, isEmpty);
    });
  });

  group('filterByCredits', () {
    test('filters by min credits', () {
      final results = CourseUtils.filterByCredits(courses, 4, null);
      expect(results.length, 1); // CS F111 has 4 total
    });

    test('filters by max credits', () {
      final results = CourseUtils.filterByCredits(courses, null, 3);
      expect(results.every((c) => c.totalCredits <= 3), isTrue);
    });

    test('null bounds returns all', () {
      expect(CourseUtils.filterByCredits(courses, null, null).length, courses.length);
    });
  });

  group('filterByDays', () {
    test('empty days returns all', () {
      expect(CourseUtils.filterByDays(courses, []).length, courses.length);
    });

    test('filters courses that have classes on Monday', () {
      final results = CourseUtils.filterByDays(courses, [DayOfWeek.M]);
      expect(results.any((c) => c.courseCode == 'CS F111'), isTrue);
      expect(results.any((c) => c.courseCode == 'MATH F112'), isTrue);
    });

    test('filters courses on Tuesday', () {
      final results = CourseUtils.filterByDays(courses, [DayOfWeek.T]);
      expect(results.any((c) => c.courseCode == 'CS F111'), isTrue);
      expect(results.any((c) => c.courseCode == 'BIO F111'), isTrue);
    });
  });

  group('filterByHours', () {
    test('empty hours returns all', () {
      expect(CourseUtils.filterByHours(courses, []).length, courses.length);
    });

    test('filters courses with hour 1 classes', () {
      final results = CourseUtils.filterByHours(courses, [1]);
      expect(results.length, 1);
      expect(results.first.courseCode, 'CS F111');
    });

    test('filters courses with lab hours', () {
      final results = CourseUtils.filterByHours(courses, [7, 8]);
      expect(results.length, 1);
      expect(results.first.courseCode, 'CS F111');
    });
  });
}
