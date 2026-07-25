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

  group('week shape', () {
    // Mon 8,9,10 then 1 PM; Tue 12 PM; Sat 11 AM. Hour 1 = 8 AM, 5 = 12 PM.
    List<Course> awkwardWeek() => [
          makeCourse(
            courseCode: 'CS F211',
            lectureCredits: 3,
            practicalCredits: 1,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1, 2, 3]),
            ],
          ),
          makeCourse(
            courseCode: 'MATH F211',
            lectureCredits: 3,
            practicalCredits: 0,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [6]),
            ],
          ),
          makeCourse(
            courseCode: 'EEE F111',
            lectureCredits: 3,
            practicalCredits: 0,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [5]),
            ],
          ),
          makeCourse(
            courseCode: 'BITS F225',
            lectureCredits: 2,
            practicalCredits: 0,
            sections: [
              makeSection(sectionId: 'L1', days: [DayOfWeek.S], hours: [4]),
            ],
          ),
        ];

    test('an 8 AM first class marks the day as an early start', () {
      final stats = TimetableStats.fromTimetable(_tt(awkwardWeek()));
      // Monday starts at hour 1; Tuesday's first class is midday.
      expect(stats.earlyStartDays, [DayOfWeek.M]);
    });

    test('gaps count every idle hour between classes, not just the longest',
        () {
      final stats = TimetableStats.fromTimetable(_tt(awkwardWeek()));
      // Monday: 8,9,10 then 1 PM — hours 4 and 5 are dead.
      expect(stats.longestGapHours, 2);
      expect(stats.longestGapDay, DayOfWeek.M);
      expect(stats.totalGapHours, 2);
    });

    test('the longest back-to-back run is the unbroken one', () {
      final stats = TimetableStats.fromTimetable(_tt(awkwardWeek()));
      // The 1 PM class is after a gap, so it does not extend the morning run.
      expect(stats.longestStreakHours, 3);
      expect(stats.longestStreakDay, DayOfWeek.M);
    });

    test('only days with a class count as class days', () {
      final stats = TimetableStats.fromTimetable(_tt(awkwardWeek()));
      expect(stats.classDayCount, 3);
    });

    test('credits are compared against the semester cap', () {
      final light = TimetableStats.fromTimetable(_tt(awkwardWeek()));
      expect(light.totalCredits, 12);
      expect(light.isOverCreditCap, isFalse);

      final heavy = TimetableStats.fromTimetable(_tt([
        ...awkwardWeek(),
        makeCourse(
          courseCode: 'PHY F211',
          lectureCredits: 12,
          practicalCredits: 2,
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.F], hours: [7]),
          ],
        ),
      ]));
      expect(heavy.totalCredits, 26);
      expect(heavy.isOverCreditCap, isTrue);
    });

    test('a day with one class is a one-hour run, not zero', () {
      final stats = TimetableStats.fromTimetable(_tt([
        makeCourse(
          courseCode: 'CS F111',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.W], hours: [3]),
          ],
        ),
      ]));
      expect(stats.longestStreakHours, 1);
      expect(stats.longestStreakDay, DayOfWeek.W);
      expect(stats.totalGapHours, 0);
      expect(stats.earlyStartDays, isEmpty);
    });
  });
}
