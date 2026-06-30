import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import '../helpers/test_data.dart';

void main() {
  group('Course', () {
    test('fromJson -> toJson roundtrip', () {
      final course = makeCourse(
        courseCode: 'CS F111',
        courseTitle: 'Computer Programming',
        midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
        endSemExam: makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.FN),
      );

      final json = course.toJson();
      final restored = Course.fromJson(json);

      expect(restored.courseCode, course.courseCode);
      expect(restored.courseTitle, course.courseTitle);
      expect(restored.lectureCredits, course.lectureCredits);
      expect(restored.practicalCredits, course.practicalCredits);
      expect(restored.totalCredits, course.totalCredits);
      expect(restored.sections.length, course.sections.length);
      expect(restored.midSemExam, isNotNull);
      expect(restored.endSemExam, isNotNull);
    });

    test('fromJson handles snake_case keys', () {
      final json = {
        'courseCode': 'CS F111',
        'courseTitle': 'Test',
        'lecture_credits': 3,
        'practical_credits': 1,
        'sections': [],
      };

      final course = Course.fromJson(json);
      expect(course.lectureCredits, 3.0);
      expect(course.practicalCredits, 1.0);
      expect(course.totalCredits, 4.0);
    });

    test('fromJson handles camelCase keys', () {
      final json = {
        'courseCode': 'CS F111',
        'courseTitle': 'Test',
        'lectureCredits': 2,
        'practicalCredits': 1,
        'sections': [],
      };

      final course = Course.fromJson(json);
      expect(course.lectureCredits, 2.0);
      expect(course.practicalCredits, 1.0);
    });

    test('fromJson with missing optional fields', () {
      final json = {
        'courseCode': 'CS F111',
        'courseTitle': 'Test',
        'sections': [],
      };

      final course = Course.fromJson(json);
      expect(course.midSemExam, isNull);
      expect(course.endSemExam, isNull);
      expect(course.sections, isEmpty);
    });
  });

  group('Section', () {
    test('fromJson -> toJson roundtrip', () {
      final section = makeSection(
        sectionId: 'L1',
        type: SectionType.L,
        days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
        hours: [1, 2],
        instructor: 'Prof X',
        room: 'F101',
      );

      final json = section.toJson();
      final restored = Section.fromJson(json);

      expect(restored.sectionId, section.sectionId);
      expect(restored.type, section.type);
      expect(restored.instructor, section.instructor);
      expect(restored.room, section.room);
      expect(restored.schedule.length, section.schedule.length);
    });

    test('fromJson tolerates missing schedule field', () {
      final json = makeSection().toJson()..remove('schedule');

      final restored = Section.fromJson(json);

      expect(restored.schedule, isEmpty);
    });

    test('fromJson tolerates null schedule field', () {
      final json = makeSection().toJson();
      json['schedule'] = null;

      final restored = Section.fromJson(json);

      expect(restored.schedule, isEmpty);
    });

    test('days getter aggregates across schedule entries', () {
      final section = Section(
        sectionId: 'L1',
        type: SectionType.L,
        instructor: 'Prof',
        room: 'R1',
        schedule: [
          ScheduleEntry(days: [DayOfWeek.M], hours: [1]),
          ScheduleEntry(days: [DayOfWeek.W], hours: [2]),
        ],
      );

      expect(section.days, containsAll([DayOfWeek.M, DayOfWeek.W]));
    });

    test('hours getter aggregates across schedule entries', () {
      final section = Section(
        sectionId: 'L1',
        type: SectionType.L,
        instructor: 'Prof',
        room: 'R1',
        schedule: [
          ScheduleEntry(days: [DayOfWeek.M], hours: [1, 2]),
          ScheduleEntry(days: [DayOfWeek.W], hours: [3]),
        ],
      );

      expect(section.hours, containsAll([1, 2, 3]));
    });
  });

  group('ScheduleEntry', () {
    test('fromJson -> toJson roundtrip', () {
      final entry = ScheduleEntry(
        days: [DayOfWeek.M, DayOfWeek.W],
        hours: [1, 2, 3],
      );

      final json = entry.toJson();
      final restored = ScheduleEntry.fromJson(json);

      expect(restored.days, entry.days);
      expect(restored.hours, entry.hours);
    });
  });

  group('ExamSchedule', () {
    test('fromJson -> toJson roundtrip', () {
      final exam = makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1);
      final json = exam.toJson();
      final restored = ExamSchedule.fromJson(json);

      expect(restored.date.year, 2026);
      expect(restored.date.month, 3);
      expect(restored.date.day, 10);
      expect(restored.timeSlot, TimeSlot.MS1);
    });

    test('fromJson strips time component from date', () {
      final json = {
        'date': '2026-03-10T14:30:00.000Z',
        'timeSlot': 'TimeSlot.MS1',
      };

      final exam = ExamSchedule.fromJson(json);
      expect(exam.date, DateTime(2026, 3, 10));
    });
  });

  group('TimeSlotInfo', () {
    test('getHourSlotName returns valid name', () {
      final name = TimeSlotInfo.getHourSlotName(1);
      expect(name, isNotEmpty);
    });
  });
}
