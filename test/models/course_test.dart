import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
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
      // No stored total → falls back to L + P.
      expect(course.totalCredits, 4.0);
    });

    test('fromJson uses a stored total_credits (U) over L + P', () {
      // A project course: PDF gives "- - 3" → L=0, P=0, but 3 units.
      final course = Course.fromJson({
        'courseCode': 'BIO F231',
        'courseTitle': 'Biology Project',
        'lecture_credits': 0,
        'practical_credits': 0,
        'total_credits': 3,
        'sections': [],
      });
      expect(course.lectureCredits, 0.0);
      expect(course.practicalCredits, 0.0);
      expect(course.totalCredits, 3.0); // not 0
    });

    test('fromJson honours a total that differs from L + P', () {
      final course = Course.fromJson({
        'courseCode': 'BITS E584',
        'lecture_credits': 3,
        'practical_credits': 0,
        'total_credits': 4, // U is 4, not 3
        'sections': [],
      });
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

    test('credit hours are read, and never derived from units', () {
      // Pilani CHEM U101: 7 contact hours, and its unit count is not published.
      // 7 is not 3 x anything — deriving either number from the other is wrong.
      final course = Course.fromJson({
        'courseCode': 'CHEM U101',
        'total_credits': 0,
        'total_credit_hours': 7,
        'com_codes': [5236],
        'sections': [],
      });
      expect(course.totalCreditHours, 7.0);
      expect(course.totalCredits, 0.0);
      expect(course.comCodes, [5236]);
    });

    test('a course with no published hours reports 0, not its units', () {
      final course = Course.fromJson({
        'courseCode': 'CS F211',
        'total_credits': 4,
        'sections': [],
      });
      expect(course.totalCreditHours, 0.0);
    });

    test('variants expose both ways a two-com-cod course is offered', () {
      final course = Course.fromJson({
        'courseCode': 'CS G569',
        'total_credits': 4,
        'total_credit_hours': 12,
        'com_codes': [2986, 6221],
        'variants': [
          {'com_code': 2986, 'credits': 4, 'credit_hours': 0},
          {'com_code': 6221, 'credits': 0, 'credit_hours': 12},
        ],
        'sections': [],
      });
      expect(course.hasVariantChoice, isTrue);
      expect(course.variants.map((v) => v.comCode), [2986, 6221]);
      expect(course.variants.first.isInHours, isFalse);
      expect(course.variants.last.isInHours, isTrue);
      // Survives a round trip, so an in-app copy of a course keeps the choice.
      expect(Course.fromJson(course.toJson()).variants.length, 2);
    });

    test('an ordinary course still has exactly one variant', () {
      // So nothing has to branch on "does this course have variants".
      final course = Course.fromJson({
        'courseCode': 'CS F211',
        'total_credits': 4,
        'com_codes': [2423],
        'sections': [],
      });
      expect(course.hasVariantChoice, isFalse);
      expect(course.variants.length, 1);
      expect(course.variants.single.credits, 4.0);
      expect(course.variants.single.comCode, 2423);
    });

    test('a generated timetable says what its number counts', () {
      // The card renders totalCredits with a "cr" suffix, so a credit-hours run
      // used to read "48.0 cr" — the right number under the wrong name.
      final hours = GeneratedTimetable(
        id: 'x',
        sections: const [],
        pros: const [],
        cons: const [],
        hoursPerDay: const {},
        totalCredits: 48,
        creditBasis: CreditBasis.hours,
      );
      expect(hours.creditBasis, CreditBasis.hours);

      // And the default is units, so nothing existing changes meaning.
      expect(
        GeneratedTimetable(
          id: 'x',
          sections: const [],
          pros: const [],
          cons: const [],
          hoursPerDay: const {},
          totalCredits: 20,
        ).creditBasis,
        CreditBasis.units,
      );
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

    test('fromJson degrades gracefully on an unknown section type', () {
      final restored = Section.fromJson({
        'sectionId': 'L1',
        'type': 'SectionType.Z',
        'instructor': 'Prof',
        'room': 'R1',
        'schedule': [],
      });
      expect(restored.type, SectionType.L); // safe default
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

    test('fromJson drops an unrecognised day instead of crashing', () {
      final restored = ScheduleEntry.fromJson({
        'days': ['DayOfWeek.M', 'DayOfWeek.Sun', 'DayOfWeek.W'],
        'hours': [1, 2],
      });
      // The bad 'Sun' is dropped; the valid days survive.
      expect(restored.days, [DayOfWeek.M, DayOfWeek.W]);
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

    test('fromJson keeps the date when the slot is unrecognised', () {
      final exam = ExamSchedule.fromJson({
        'date': '2026-03-10T00:00:00.000Z',
        'timeSlot': 'TimeSlot.XYZ',
      });
      expect(exam.date, DateTime(2026, 3, 10)); // date preserved
      expect(exam.timeSlot, TimeSlot.FN); // safe fallback, no crash
    });
  });

  group('TimeSlotInfo', () {
    test('getHourSlotName returns valid name', () {
      final name = TimeSlotInfo.getHourSlotName(1);
      expect(name, isNotEmpty);
    });
  });
}
