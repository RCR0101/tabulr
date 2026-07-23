import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_stats.dart';

import '../helpers/test_data.dart';

Timetable _tt(List<Course> courses) => Timetable(
      id: 't1',
      name: 'T',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      campus: Campus.hyderabad,
      availableCourses: courses,
      selectedSections: [
        for (final c in courses)
          makeSelectedSection(courseCode: c.courseCode, section: c.sections.first),
      ],
      clashWarnings: [],
    );

void main() {
  group('TimetableStats.allExams', () {
    test('collects every exam, sorted by date then session', () {
      final courses = [
        makeCourse(courseCode: 'CS F111', midSemExam: makeExam(date: DateTime(2026, 3, 12))),
        makeCourse(courseCode: 'MATH F111', midSemExam: makeExam(date: DateTime(2026, 3, 10))),
        makeCourse(courseCode: 'PHY F111', endSemExam: makeExam(date: DateTime(2026, 5, 2))),
      ];
      final stats = TimetableStats.fromTimetable(_tt(courses));

      expect(stats.allExams, hasLength(3));
      // Sorted ascending by date.
      expect(stats.allExams.map((e) => e.courseCode),
          ['MATH F111', 'CS F111', 'PHY F111']);
      expect(stats.allExams.first.isMidSem, isTrue);
      expect(stats.allExams.last.isMidSem, isFalse);
    });

    test('two exams a day apart form a cluster', () {
      final courses = [
        makeCourse(courseCode: 'A', midSemExam: makeExam(date: DateTime(2026, 3, 10))),
        makeCourse(courseCode: 'B', midSemExam: makeExam(date: DateTime(2026, 3, 11))),
        makeCourse(courseCode: 'C', midSemExam: makeExam(date: DateTime(2026, 4, 1))),
      ];
      final stats = TimetableStats.fromTimetable(_tt(courses));

      expect(stats.hasExamClusters, isTrue);
      expect(stats.worstClusterSize, 2);
      // The lone April exam is still in allExams but not in any cluster.
      expect(stats.allExams, hasLength(3));
    });

    test('no exams yields an empty timeline', () {
      final stats = TimetableStats.fromTimetable(
          _tt([makeCourse(courseCode: 'CS F111')]));
      expect(stats.allExams, isEmpty);
      expect(stats.hasExamClusters, isFalse);
    });
  });
}
