import 'course.dart';

class TimetableConstraints {
  final List<String> requiredCourses;
  final List<TimeAvoidance> avoidTimes;
  final List<LabAvoidance> avoidLabs;
  final int maxHoursPerDay;
  final List<String> preferredInstructors;
  final List<String> avoidedInstructors;
  final bool avoidBackToBackClasses;
  final TimeSlot? preferredExamSlot;
  final Map<String, InstructorRankings> instructorRankings;

  TimetableConstraints({
    required this.requiredCourses,
    this.avoidTimes = const [],
    this.avoidLabs = const [],
    this.maxHoursPerDay = 8,
    this.preferredInstructors = const [],
    this.avoidedInstructors = const [],
    this.avoidBackToBackClasses = false,
    this.preferredExamSlot,
    this.instructorRankings = const {},
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

class LabAvoidance {
  final DayOfWeek day;
  final List<int> hours;

  LabAvoidance({
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

class InstructorRankings {
  final List<String> lectureInstructors;
  final List<String> practicalInstructors;
  final List<String> tutorialInstructors;

  InstructorRankings({
    this.lectureInstructors = const [],
    this.practicalInstructors = const [],
    this.tutorialInstructors = const [],
  });

  InstructorRankings copyWith({
    List<String>? lectureInstructors,
    List<String>? practicalInstructors,
    List<String>? tutorialInstructors,
  }) {
    return InstructorRankings(
      lectureInstructors: lectureInstructors ?? this.lectureInstructors,
      practicalInstructors: practicalInstructors ?? this.practicalInstructors,
      tutorialInstructors: tutorialInstructors ?? this.tutorialInstructors,
    );
  }

  int getInstructorRank(String instructor, SectionType sectionType) {
    List<String> relevantList;
    switch (sectionType) {
      case SectionType.L:
        relevantList = lectureInstructors;
        break;
      case SectionType.P:
        relevantList = practicalInstructors;
        break;
      case SectionType.T:
        relevantList = tutorialInstructors;
        break;
    }
    
    final index = relevantList.indexOf(instructor);
    if (index == -1) return 0; // Not ranked
    
    // Higher rank for earlier position (most preferred first)
    return relevantList.length - index;
  }
}

enum TimetableIssueType {
  courseNotFound,
  noSectionsAvailable,
  scheduleConflict,
  examConflict,
  instructorConflict,
  timeConstraintConflict,
  labConstraintConflict,
  hourLimitExceeded,
  incompatibleCombination,
  noValidCombinations,
}

class TimetableIssue {
  final TimetableIssueType type;
  final String message;
  final List<String> affectedCourses;
  final String? suggestion;
  final Map<String, dynamic> details;

  TimetableIssue({
    required this.type,
    required this.message,
    this.affectedCourses = const [],
    this.suggestion,
    this.details = const {},
  });
}

class TimetableGenerationResult {
  final List<GeneratedTimetable> timetables;
  final List<TimetableIssue> issues;
  final Map<String, dynamic> statistics;
  final bool hasErrors;
  final bool hasWarnings;

  TimetableGenerationResult({
    required this.timetables,
    required this.issues,
    this.statistics = const {},
  }) : hasErrors = issues.any((issue) => _isErrorType(issue.type)),
       hasWarnings = issues.any((issue) => !_isErrorType(issue.type));

  static bool _isErrorType(TimetableIssueType type) {
    return [
      TimetableIssueType.courseNotFound,
      TimetableIssueType.noSectionsAvailable,
      TimetableIssueType.noValidCombinations,
    ].contains(type);
  }
}