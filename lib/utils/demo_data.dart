import '../models/academic_calendar_event.dart';
import '../models/campus.dart';
import '../models/cgpa_data.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../models/timetable_constraints.dart';
import '../models/timetable_stats.dart';
import '../services/core/timetable_ranker.dart';

abstract final class DemoData {
  static Section _section({
    required String id,
    SectionType type = SectionType.L,
    required List<DayOfWeek> days,
    required List<int> hours,
    required String instructor,
    required String room,
  }) =>
      Section(
        sectionId: id,
        type: type,
        instructor: instructor,
        room: room,
        schedule: [ScheduleEntry(days: [...days], hours: [...hours])],
      );

  static final List<Course> courses = [
    Course(
      courseCode: 'CS F211',
      courseTitle: 'Data Structures & Algorithms',
      lectureCredits: 3,
      practicalCredits: 1,
      totalCredits: 4,
      sections: [
        _section(
          id: 'L1',
          days: const [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
          hours: const [2],
          instructor: 'Dr. R Menon',
          room: 'F102',
        ),
        _section(
          id: 'P1',
          type: SectionType.P,
          days: const [DayOfWeek.W],
          hours: const [5, 6],
          instructor: 'Dr. R Menon',
          room: 'Lab 3',
        ),
      ],
      midSemExam: ExamSchedule(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
      endSemExam: ExamSchedule(date: DateTime(2026, 5, 12), timeSlot: TimeSlot.FN),
    ),
    Course(
      courseCode: 'MATH F211',
      courseTitle: 'Mathematics III',
      lectureCredits: 3,
      practicalCredits: 0,
      totalCredits: 3,
      sections: [
        _section(
          id: 'L2',
          days: const [DayOfWeek.T, DayOfWeek.Th],
          hours: const [3, 4],
          instructor: 'Dr. S Iyer',
          room: 'F215',
        ),
      ],
      midSemExam: ExamSchedule(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
      endSemExam: ExamSchedule(date: DateTime(2026, 5, 14), timeSlot: TimeSlot.AN),
    ),
    Course(
      courseCode: 'EEE F111',
      courseTitle: 'Electrical Sciences',
      lectureCredits: 3,
      practicalCredits: 1,
      totalCredits: 4,
      sections: [
        _section(
          id: 'L1',
          days: const [DayOfWeek.M, DayOfWeek.W],
          hours: const [1],
          instructor: 'Dr. A Bhat',
          room: 'F103',
        ),
        _section(
          id: 'T1',
          type: SectionType.T,
          days: const [DayOfWeek.S],
          hours: const [4],
          instructor: 'Dr. A Bhat',
          room: 'F110',
        ),
      ],
      midSemExam: ExamSchedule(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS1),
      endSemExam: ExamSchedule(date: DateTime(2026, 5, 15), timeSlot: TimeSlot.FN),
    ),
    Course(
      courseCode: 'HSS F236',
      courseTitle: 'Introduction to Film Studies',
      lectureCredits: 3,
      practicalCredits: 0,
      totalCredits: 3,
      sections: [
        _section(
          id: 'L1',
          days: const [DayOfWeek.Th],
          hours: const [7, 8],
          instructor: 'Dr. P Nair',
          room: 'G201',
        ),
      ],
      midSemExam: ExamSchedule(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS4),
      endSemExam: ExamSchedule(date: DateTime(2026, 5, 18), timeSlot: TimeSlot.AN),
    ),
    Course(
      courseCode: 'BITS F225',
      courseTitle: 'Environmental Studies',
      lectureCredits: 3,
      practicalCredits: 0,
      totalCredits: 3,
      sections: [
        _section(
          id: 'L1',
          days: const [DayOfWeek.T],
          hours: const [8],
          instructor: 'Dr. K Rao',
          room: 'F204',
        ),
      ],
      midSemExam: ExamSchedule(date: DateTime(2026, 3, 13), timeSlot: TimeSlot.MS3),
    ),
  ];

  static final List<SelectedSection> selections = [
    for (final course in courses)
      for (final section in course.sections)
        SelectedSection(
          courseCode: course.courseCode,
          sectionId: section.sectionId,
          section: section,
        ),
  ];

  static final List<TimetableSlot> slots = [
    for (final course in courses)
      for (final section in course.sections)
        for (final entry in section.schedule)
          for (final day in entry.days)
            TimetableSlot(
              day: day,
              hours: entry.hours,
              courseCode: course.courseCode,
              courseTitle: course.courseTitle,
              sectionId: section.sectionId,
              instructor: section.instructor,
              room: section.room,
            ),
  ];

  static final Timetable timetable = Timetable(
    id: 'guide-demo',
    name: 'Semester 1',
    createdAt: DateTime(2026, 1, 4),
    updatedAt: DateTime(2026, 1, 4),
    campus: Campus.hyderabad,
    availableCourses: courses,
    selectedSections: selections,
    clashWarnings: const [],
  );

  static final List<ClashWarning> clashes = [
    ClashWarning(
      type: ClashType.regularClass,
      message: 'CS F211 L1 and EEE F111 L1 both meet Monday, hour 2',
      conflictingCourses: const ['CS F211', 'EEE F111'],
      severity: ClashSeverity.error,
    ),
    ClashWarning(
      type: ClashType.midSemExam,
      message: 'CS F211 and HSS F236 have midsems on the same day',
      conflictingCourses: const ['CS F211', 'HSS F236'],
      severity: ClashSeverity.warning,
      examDate: DateTime(2026, 3, 12),
    ),
  ];

  static const Map<DayOfWeek, int> hoursPerDay = {
    DayOfWeek.M: 3,
    DayOfWeek.T: 4,
    DayOfWeek.W: 5,
    DayOfWeek.Th: 4,
    DayOfWeek.F: 1,
    DayOfWeek.S: 1,
  };

  static final List<ExamEntry> exams = [
    for (final course in courses) ...[
      if (course.midSemExam != null)
        ExamEntry(
          courseCode: course.courseCode,
          courseTitle: course.courseTitle,
          date: course.midSemExam!.date,
          timeSlot: course.midSemExam!.timeSlot,
          isMidSem: true,
        ),
      if (course.endSemExam != null)
        ExamEntry(
          courseCode: course.courseCode,
          courseTitle: course.courseTitle,
          date: course.endSemExam!.date,
          timeSlot: course.endSemExam!.timeSlot,
          isMidSem: false,
        ),
    ],
  ];

  static final List<ExamCluster> examClusters = [
    ExamCluster(
      exams: exams.where((e) => e.isMidSem && e.date.day >= 10 && e.date.day <= 12).toList(),
      startDate: DateTime(2026, 3, 10),
      endDate: DateTime(2026, 3, 12),
      spanDays: 2,
    ),
  ];

  static final List<AcademicCalendarEvent> calendarEvents = [
    AcademicCalendarEvent(
      date: DateTime(2026, 1, 5),
      label: 'Classwork begins',
      category: AcademicEventCategory.milestone,
    ),
    AcademicCalendarEvent(
      date: DateTime(2026, 1, 16),
      label: 'Last date to drop a course',
      category: AcademicEventCategory.deadline,
    ),
    AcademicCalendarEvent(
      date: DateTime(2026, 3, 4),
      label: 'Holi',
      category: AcademicEventCategory.holiday,
    ),
    AcademicCalendarEvent(
      date: DateTime(2026, 3, 10),
      endDate: DateTime(2026, 3, 16),
      label: 'Mid-semester examinations',
      category: AcademicEventCategory.exam,
    ),
    AcademicCalendarEvent(
      date: DateTime(2026, 5, 12),
      endDate: DateTime(2026, 5, 20),
      label: 'Comprehensive examinations',
      category: AcademicEventCategory.exam,
    ),
  ];

  static final RankedTimetable rankedTimetable = RankedTimetable(
    timetable: GeneratedTimetable(
      id: 'Friday off, light mornings',
      sections: [
        for (final course in courses)
          for (final section in course.sections)
            ConstraintSelectedSection(
              courseCode: course.courseCode,
              sectionId: section.sectionId,
              section: section,
            ),
      ],
      pros: const [
        'Friday is completely free',
        'No 8 AM classes after Monday',
        'Midsems spread over four days',
      ],
      cons: const ['Wednesday runs five hours'],
      hoursPerDay: hoursPerDay,
      totalCredits: 17,
    ),
    tier: 1,
    closeness: 0.86,
    axisSatisfaction: const {
      RankAxis.freeDays: 0.9,
      RankAxis.lightLoad: 0.62,
      RankAxis.timeFit: 0.81,
      RankAxis.examComfort: 0.55,
    },
    weakAxes: const [RankAxis.examComfort],
  );

  static const Map<RankAxis, AxisImportance> axisImportance = {
    RankAxis.freeDays: AxisImportance.high,
    RankAxis.lightLoad: AxisImportance.normal,
    RankAxis.timeFit: AxisImportance.normal,
    RankAxis.instructors: AxisImportance.low,
    RankAxis.examComfort: AxisImportance.high,
    RankAxis.coursesFitted: AxisImportance.normal,
  };

  static const List<CgpaTrajectoryPoint> trajectory = [
    (semester: '2024-25 · 1', sgpa: 7.6, cumulativeCgpa: 7.60, credits: 20),
    (semester: '2024-25 · 2', sgpa: 8.4, cumulativeCgpa: 8.00, credits: 21),
    (semester: '2025-26 · 1', sgpa: 8.1, cumulativeCgpa: 8.04, credits: 19),
    (semester: '2025-26 · 2', sgpa: 9.0, cumulativeCgpa: 8.29, credits: 22),
  ];
}
