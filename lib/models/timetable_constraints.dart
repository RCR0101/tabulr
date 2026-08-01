import 'course.dart';

/// User preferences fed to [TimetableGenerator.generateTimetables].
///
/// Mandatory courses must all appear in every generated timetable; optional
/// courses are greedily added if they fit within [maxCredits] and don't
/// introduce clashes. Ordering of [optionalCourses] encodes user priority.
class TimetableConstraints {
  final List<String> mandatoryCourses;

  /// Ordered by user preference (first = most wanted).
  final List<String> optionalCourses;

  /// Cap on how many [optionalCourses] to include ("any N of M"). Null means
  /// fit as many as credits and clashes allow.
  final int? optionalTarget;

  /// Ceiling on the run's total load, in whatever [creditBasis] counts.
  ///
  /// Null means "the published cap for that basis" — which is the right default
  /// precisely because it differs per basis: hard-coding 25 here measured a
  /// contact-hours run against the unit cap.
  final double? maxCredits;

  /// What this run counts in. Explicit rather than inferred from the mandatory
  /// courses: with none selected there is nothing to infer from, and a student
  /// who picks only optionals would silently get a credits run.
  final CreditBasis creditBasis;
  final List<TimeAvoidance> avoidTimes;
  final List<LabAvoidance> avoidLabs;
  final int maxHoursPerDay;
  final List<String> preferredInstructors;
  final List<String> avoidedInstructors;
  final bool avoidBackToBackClasses;
  final Map<String, InstructorRankings> instructorRankings;
  final List<DayOfWeek> freeDayPreference;
  final bool minimizeGaps;
  final TimeOfDayPreference timeOfDayPreference;
  final bool protectLunchBreak;

  /// Preferred class-hours window as hour-slot numbers (1 = 8 AM … 12 = 7 PM).
  /// Null means "no bound" on that side. Classes outside the window are
  /// penalised (soft), not excluded.
  final int? earliestStartSlot;
  final int? latestEndSlot;

  /// Advanced opt-in: promote a soft intent to a *hard* pre-filter. A timetable
  /// violating a required intent is excluded outright — which can legitimately
  /// return zero results. Each only bites when its underlying soft intent is
  /// also set (a window, free-day list, or lunch protection).
  final bool requireHoursWindow;
  final bool requireFreeDays;
  final bool requireLunchFree;

  final TimeSlot? preferredMidsemSlot;
  final TimeSlot? preferredCompreSlot;

  TimetableConstraints({
    this.mandatoryCourses = const [],
    this.optionalCourses = const [],
    this.optionalTarget,
    this.maxCredits,
    this.creditBasis = CreditBasis.units,
    this.avoidTimes = const [],
    this.avoidLabs = const [],
    this.maxHoursPerDay = 8,
    this.preferredInstructors = const [],
    this.avoidedInstructors = const [],
    this.avoidBackToBackClasses = false,
    this.instructorRankings = const {},
    this.freeDayPreference = const [],
    this.minimizeGaps = false,
    this.timeOfDayPreference = TimeOfDayPreference.none,
    this.protectLunchBreak = false,
    this.earliestStartSlot,
    this.latestEndSlot,
    this.requireHoursWindow = false,
    this.requireFreeDays = false,
    this.requireLunchFree = false,
    this.preferredMidsemSlot,
    this.preferredCompreSlot,
  });
}

/// A day + hour range the user wants to keep free from classes.
class TimeAvoidance {
  final DayOfWeek day;
  final List<int> hours;

  TimeAvoidance({
    required this.day,
    required this.hours,
  });
}

/// Like [TimeAvoidance] but only penalizes practical (lab) sections.
class LabAvoidance {
  final DayOfWeek day;
  final List<int> hours;

  LabAvoidance({
    required this.day,
    required this.hours,
  });
}

/// One candidate timetable produced by [TimetableGenerator].
///
/// [score] is 0–100 (base 90 − penalties + bonuses). [pros] and [cons]
/// are human-readable analysis strings shown in the comparison UI.
class GeneratedTimetable {
  /// Descriptive name assigned by the generator (e.g. "Mon off, light days").
  final String id;
  final List<ConstraintSelectedSection> sections;
  final List<String> pros;
  final List<String> cons;
  final Map<DayOfWeek, int> hoursPerDay;
  final double totalCredits;

  /// What [totalCredits] counts — the run's basis, so the card can label the
  /// number instead of assuming units.
  final CreditBasis creditBasis;
  final Set<String> optionalCourseCodes;

  GeneratedTimetable({
    required this.id,
    required this.sections,
    required this.pros,
    required this.cons,
    required this.hoursPerDay,
    this.totalCredits = 0,
    this.creditBasis = CreditBasis.units,
    this.optionalCourseCodes = const {},
  });
}

/// Generator-internal version of [SelectedSection] (avoids importing timetable.dart).
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

/// Per-course instructor preference lists, one per section type.
/// First element = most preferred. [getInstructorRank] returns a score
/// proportional to list position (higher = more preferred).
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

/// A problem detected during timetable generation (e.g. missing course,
/// unresolvable conflict). Shown in the generation results UI.
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

/// Wraps the output of a generation run: candidate timetables, any issues
/// encountered, and aggregate statistics.
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

enum TimeOfDayPreference {
  none,
  morning,
  afternoon,
}