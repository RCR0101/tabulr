import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/services/core/course_comparison_service.dart';
import '../helpers/test_data.dart';

void main() {
  group('calculateSimilarityScore', () {
    test('identical schedules produce score of 1.0', () {
      final a = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [1]),
        ],
        midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.FN),
        endSemExam: makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.AN),
      );
      final b = makeCourse(
        courseCode: 'MATH F112',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [1]),
        ],
        midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.FN),
        endSemExam: makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.AN),
      );

      final score = CourseComparisonService.calculateSimilarityScore(a, b);
      expect(score, 1.0);
    });

    test('completely different schedules produce score near 0', () {
      final a = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
        ],
      );
      final b = makeCourse(
        courseCode: 'BIO F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.F], hours: [8]),
        ],
      );

      final score = CourseComparisonService.calculateSimilarityScore(a, b);
      expect(score, lessThan(0.3));
    });

    test('partial day overlap produces intermediate score', () {
      final a = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
        ],
      );
      final b = makeCourse(
        courseCode: 'MATH F112',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.T], hours: [1]),
        ],
      );

      final score = CourseComparisonService.calculateSimilarityScore(a, b);
      expect(score, greaterThan(0.0));
      expect(score, lessThan(1.0));
    });

    test('courses with no sections produce 0', () {
      final a = makeCourse(courseCode: 'A', sections: []);
      final b = makeCourse(courseCode: 'B', sections: []);

      expect(CourseComparisonService.calculateSimilarityScore(a, b), 0.0);
    });
  });

  group('findSimilarCourses', () {
    test('skips the reference course itself', () {
      final ref = makeCourse(
        courseCode: 'CS F111',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
      );
      final others = [
        ref,
        makeCourse(
          courseCode: 'MATH F112',
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
      ];

      final results = CourseComparisonService.findSimilarCourses(ref, others);
      expect(results.length, 1);
      expect(results.first.course.courseCode, 'MATH F112');
    });

    test('results are sorted by similarity descending', () {
      final ref = makeCourse(
        courseCode: 'REF',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [1])],
      );
      final exact = makeCourse(
        courseCode: 'EXACT',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [1])],
      );
      final partial = makeCourse(
        courseCode: 'PARTIAL',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
      );
      final none = makeCourse(
        courseCode: 'NONE',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.F], hours: [8])],
      );

      final results = CourseComparisonService.findSimilarCourses(ref, [exact, partial, none]);
      expect(results[0].course.courseCode, 'EXACT');
      expect(results[0].similarityScore, greaterThanOrEqualTo(results[1].similarityScore));
      expect(results[1].similarityScore, greaterThanOrEqualTo(results[2].similarityScore));
    });

    test('limit caps results', () {
      final ref = makeCourse(
        courseCode: 'REF',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
      );
      final courses = List.generate(
        10,
        (i) => makeCourse(
          courseCode: 'C$i',
          sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
        ),
      );

      final results = CourseComparisonService.findSimilarCourses(ref, courses, limit: 3);
      expect(results.length, 3);
    });

    test('returns empty list when there are no other courses', () {
      final ref = makeCourse(courseCode: 'REF');
      expect(CourseComparisonService.findSimilarCourses(ref, []), isEmpty);
      expect(CourseComparisonService.findSimilarCourses(ref, [ref]), isEmpty);
    });

    test('does not throw when reference or candidate has no sections', () {
      final ref = makeCourse(courseCode: 'REF', sections: []);
      final other = makeCourse(courseCode: 'OTHER', sections: []);

      final results = CourseComparisonService.findSimilarCourses(ref, [other]);
      expect(results, hasLength(1));
      expect(results.first.similarityScore, inInclusiveRange(0.0, 1.0));
    });
  });

  group('hasOnlyLectureSections', () {
    test('true when all sections are lectures', () {
      final course = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', type: SectionType.L),
          makeSection(sectionId: 'L2', type: SectionType.L),
        ],
      );
      expect(CourseComparisonService.hasOnlyLectureSections(course), isTrue);
    });

    test('false when practicals exist', () {
      final course = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', type: SectionType.L),
          makeSection(sectionId: 'P1', type: SectionType.P),
        ],
      );
      expect(CourseComparisonService.hasOnlyLectureSections(course), isFalse);
    });

    test('false when no sections at all', () {
      final course = makeCourse(courseCode: 'EMPTY', sections: []);
      expect(CourseComparisonService.hasOnlyLectureSections(course), isFalse);
    });
  });
}
