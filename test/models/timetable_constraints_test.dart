import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';

void main() {
  group('TimetableConstraints', () {
    test('default values are sensible', () {
      final c = TimetableConstraints();
      expect(c.mandatoryCourses, isEmpty);
      expect(c.optionalCourses, isEmpty);
      expect(c.maxCredits, 25);
      expect(c.maxHoursPerDay, 8);
      expect(c.avoidBackToBackClasses, isFalse);
      expect(c.minimizeGaps, isFalse);
      expect(c.timeOfDayPreference, TimeOfDayPreference.none);
    });
  });

  group('InstructorRankings', () {
    test('getInstructorRank returns correct rank for ranked instructor', () {
      final rankings = InstructorRankings(
        lectureInstructors: ['Prof A', 'Prof B', 'Prof C'],
      );

      // First position = highest rank = length - 0 = 3
      expect(rankings.getInstructorRank('Prof A', SectionType.L), 3);
      expect(rankings.getInstructorRank('Prof B', SectionType.L), 2);
      expect(rankings.getInstructorRank('Prof C', SectionType.L), 1);
    });

    test('getInstructorRank returns 0 for unranked instructor', () {
      final rankings = InstructorRankings(
        lectureInstructors: ['Prof A'],
      );

      expect(rankings.getInstructorRank('Unknown Prof', SectionType.L), 0);
    });

    test('getInstructorRank uses correct list per section type', () {
      final rankings = InstructorRankings(
        lectureInstructors: ['Lecture Prof'],
        practicalInstructors: ['Lab Prof'],
        tutorialInstructors: ['Tutorial Prof'],
      );

      expect(rankings.getInstructorRank('Lecture Prof', SectionType.L), 1);
      expect(rankings.getInstructorRank('Lab Prof', SectionType.P), 1);
      expect(rankings.getInstructorRank('Tutorial Prof', SectionType.T), 1);

      // Wrong type returns 0
      expect(rankings.getInstructorRank('Lecture Prof', SectionType.P), 0);
    });

    test('copyWith preserves unchanged fields', () {
      final original = InstructorRankings(
        lectureInstructors: ['A'],
        practicalInstructors: ['B'],
        tutorialInstructors: ['C'],
      );

      final copied = original.copyWith(lectureInstructors: ['X', 'Y']);
      expect(copied.lectureInstructors, ['X', 'Y']);
      expect(copied.practicalInstructors, ['B']);
      expect(copied.tutorialInstructors, ['C']);
    });
  });

  group('GeneratedTimetable', () {
    test('stores sections and score', () {
      final tt = GeneratedTimetable(
        id: 'gen-1',
        sections: [
          ConstraintSelectedSection(
            courseCode: 'CS F111',
            sectionId: 'L1',
            section: Section(
              sectionId: 'L1',
              type: SectionType.L,
              instructor: 'Prof',
              room: 'R1',
              schedule: [ScheduleEntry(days: [DayOfWeek.M], hours: [1])],
            ),
          ),
        ],
        score: 85.5,
        pros: ['No gaps'],
        cons: ['Early morning'],
        hoursPerDay: {DayOfWeek.M: 1},
        totalCredits: 3,
        optionalCourseCodes: {'OPT F100'},
      );

      expect(tt.sections.length, 1);
      expect(tt.score, 85.5);
      expect(tt.pros, contains('No gaps'));
      expect(tt.optionalCourseCodes, contains('OPT F100'));
    });
  });

  group('TimeOfDayPreference', () {
    test('has all expected values', () {
      expect(TimeOfDayPreference.values, contains(TimeOfDayPreference.none));
      expect(TimeOfDayPreference.values.length, greaterThanOrEqualTo(2));
    });
  });
}
