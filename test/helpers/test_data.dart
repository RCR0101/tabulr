import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';

Section makeSection({
  String sectionId = 'L1',
  SectionType type = SectionType.L,
  List<DayOfWeek> days = const [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
  List<int> hours = const [1],
  String instructor = 'Prof X',
  String room = 'F101',
}) {
  return Section(
    sectionId: sectionId,
    type: type,
    instructor: instructor,
    room: room,
    schedule: [ScheduleEntry(days: days, hours: hours)],
  );
}

Course makeCourse({
  String courseCode = 'CS F111',
  String courseTitle = 'Computer Programming',
  double lectureCredits = 3,
  double practicalCredits = 1,
  List<Section>? sections,
  ExamSchedule? midSemExam,
  ExamSchedule? endSemExam,
}) {
  return Course(
    courseCode: courseCode,
    courseTitle: courseTitle,
    lectureCredits: lectureCredits,
    practicalCredits: practicalCredits,
    totalCredits: lectureCredits + practicalCredits,
    sections: sections ?? [makeSection()],
    midSemExam: midSemExam,
    endSemExam: endSemExam,
  );
}

SelectedSection makeSelectedSection({
  String courseCode = 'CS F111',
  String sectionId = 'L1',
  Section? section,
}) {
  return SelectedSection(
    courseCode: courseCode,
    sectionId: sectionId,
    section: section ?? makeSection(sectionId: sectionId),
  );
}

ExamSchedule makeExam({
  DateTime? date,
  TimeSlot timeSlot = TimeSlot.FN,
}) {
  return ExamSchedule(
    date: date ?? DateTime(2026, 5, 10),
    timeSlot: timeSlot,
  );
}

// --- Predefined fixtures ---

/// Two courses on different days — no clash possible.
List<Course> twoCourseNoClash() => [
  makeCourse(
    courseCode: 'CS F111',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [1]),
      makeSection(sectionId: 'T1', type: SectionType.T, days: [DayOfWeek.F], hours: [5]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
  ),
  makeCourse(
    courseCode: 'MATH F112',
    courseTitle: 'Mathematics I',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.T, DayOfWeek.Th], hours: [2]),
      makeSection(sectionId: 'T1', type: SectionType.T, days: [DayOfWeek.S], hours: [6]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
  ),
];

/// Two courses on the SAME day + hour — guaranteed clash.
List<Course> twoCourseSameSlot() => [
  makeCourse(
    courseCode: 'CS F111',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
  ),
  makeCourse(
    courseCode: 'CS F211',
    courseTitle: 'Data Structures',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
  ),
];

/// Five courses with multiple sections each — realistic load for generator.
List<Course> fiveCourseRealistic() => [
  makeCourse(
    courseCode: 'CS F111',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
      makeSection(sectionId: 'L2', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [2]),
      makeSection(sectionId: 'T1', type: SectionType.T, days: [DayOfWeek.T], hours: [5]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
    endSemExam: makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.FN),
  ),
  makeCourse(
    courseCode: 'MATH F112',
    courseTitle: 'Mathematics I',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.T, DayOfWeek.Th], hours: [2, 3]),
      makeSection(sectionId: 'L2', days: [DayOfWeek.T, DayOfWeek.Th], hours: [4, 5]),
      makeSection(sectionId: 'T1', type: SectionType.T, days: [DayOfWeek.W], hours: [6]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
    endSemExam: makeExam(date: DateTime(2026, 5, 12), timeSlot: TimeSlot.AN),
  ),
  makeCourse(
    courseCode: 'PHY F111',
    courseTitle: 'Mechanics',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [3]),
      makeSection(sectionId: 'P1', type: SectionType.P, days: [DayOfWeek.T], hours: [7, 8]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS3),
    endSemExam: makeExam(date: DateTime(2026, 5, 14), timeSlot: TimeSlot.FN),
  ),
  makeCourse(
    courseCode: 'BIO F111',
    courseTitle: 'General Biology',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.T, DayOfWeek.Th, DayOfWeek.S], hours: [1]),
      makeSection(sectionId: 'L2', days: [DayOfWeek.T, DayOfWeek.Th, DayOfWeek.S], hours: [3]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 13), timeSlot: TimeSlot.MS4),
    endSemExam: makeExam(date: DateTime(2026, 5, 16), timeSlot: TimeSlot.AN),
  ),
  makeCourse(
    courseCode: 'EEE F111',
    courseTitle: 'Electrical Sciences',
    sections: [
      makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [4]),
      makeSection(sectionId: 'L2', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [5]),
      makeSection(sectionId: 'P1', type: SectionType.P, days: [DayOfWeek.Th], hours: [7, 8]),
    ],
    midSemExam: makeExam(date: DateTime(2026, 3, 14), timeSlot: TimeSlot.MS1),
    endSemExam: makeExam(date: DateTime(2026, 5, 18), timeSlot: TimeSlot.FN),
  ),
];
