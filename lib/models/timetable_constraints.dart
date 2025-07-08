import 'course.dart';

class TimetableConstraints {
  final List<String> requiredCourses;
  final List<TimeAvoidance> avoidTimes;
  final int maxHoursPerDay;
  final List<String> preferredInstructors;
  final List<String> avoidedInstructors;
  final bool avoidBackToBackClasses;
  final TimeSlot? preferredExamSlot;

  TimetableConstraints({
    required this.requiredCourses,
    this.avoidTimes = const [],
    this.maxHoursPerDay = 8,
    this.preferredInstructors = const [],
    this.avoidedInstructors = const [],
    this.avoidBackToBackClasses = false,
    this.preferredExamSlot,
  });
}

class TimeAvoidance {
  final DayOfWeek day;
  final List<int> hours;

  TimeAvoidance({
    required this.day,
    required this.hours,
  });
}

class GeneratedTimetable {
  final String id;
  final List<ConstraintSelectedSection> sections;
  final double score;
  final List<String> pros;
  final List<String> cons;
  final Map<DayOfWeek, int> hoursPerDay;

  GeneratedTimetable({
    required this.id,
    required this.sections,
    required this.score,
    required this.pros,
    required this.cons,
    required this.hoursPerDay,
  });
}

class ConstraintSelectedSection {
  final String courseCode;
  final String sectionId;
  final Section section;

  ConstraintSelectedSection({
    required this.courseCode,
    required this.sectionId,
    required this.section,
  });
}