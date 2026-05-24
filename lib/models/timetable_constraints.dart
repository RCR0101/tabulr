import 'course.dart';

class TimetableConstraints {
  final List<String> mandatoryCourses;
  final List<String> optionalCourses;
  final double maxCredits;
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
  final TimeSlot? preferredMidsemSlot;
  final TimeSlot? preferredCompreSlot;
  final ScoringWeights scoringWeights;

  TimetableConstraints({
    this.mandatoryCourses = const [],
    this.optionalCourses = const [],
    this.maxCredits = 25,
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
    this.preferredMidsemSlot,
    this.preferredCompreSlot,
    this.scoringWeights = const ScoringWeights(),
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
  final double totalCredits;
  final Set<String> optionalCourseCodes;

  GeneratedTimetable({
    required this.id,
    required this.sections,
    required this.score,
    required this.pros,
    required this.cons,
    required this.hoursPerDay,
    this.totalCredits = 0,
    this.optionalCourseCodes = const {},
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

class ScoringWeights {
  // Penalty caps (negative factors — higher = penalised more)
  final double maxHoursPerDayPenalty;
  final double avoidTimesPenalty;
  final double avoidLabsPenalty;
  final double avoidedInstructorsPenalty;
  final double backToBackPenalty;
  final double gapsPenalty;
  final double lunchBreakPenalty;
  final double timeOfDayPenalty;
  final double examSpreadPenalty;

  // Bonus caps (positive factors — higher = rewarded more)
  final double preferredInstructorsBonus;
  final double instructorRankingsBonus;
  final double freeDayBonus;
  final double examSlotBonus;
  final double optionalCoursesBonus;

  const ScoringWeights({
    this.maxHoursPerDayPenalty = 15,
    this.avoidTimesPenalty = 15,
    this.avoidLabsPenalty = 10,
    this.avoidedInstructorsPenalty = 15,
    this.backToBackPenalty = 8,
    this.gapsPenalty = 8,
    this.lunchBreakPenalty = 5,
    this.timeOfDayPenalty = 7,
    this.examSpreadPenalty = 7,
    this.preferredInstructorsBonus = 2,
    this.instructorRankingsBonus = 2,
    this.freeDayBonus = 3,
    this.examSlotBonus = 2,
    this.optionalCoursesBonus = 3,
  });

  static const ScoringWeights defaults = ScoringWeights();

  ScoringWeights copyWith({
    double? maxHoursPerDayPenalty,
    double? avoidTimesPenalty,
    double? avoidLabsPenalty,
    double? avoidedInstructorsPenalty,
    double? backToBackPenalty,
    double? gapsPenalty,
    double? lunchBreakPenalty,
    double? timeOfDayPenalty,
    double? examSpreadPenalty,
    double? preferredInstructorsBonus,
    double? instructorRankingsBonus,
    double? freeDayBonus,
    double? examSlotBonus,
    double? optionalCoursesBonus,
  }) {
    return ScoringWeights(
      maxHoursPerDayPenalty: maxHoursPerDayPenalty ?? this.maxHoursPerDayPenalty,
      avoidTimesPenalty: avoidTimesPenalty ?? this.avoidTimesPenalty,
      avoidLabsPenalty: avoidLabsPenalty ?? this.avoidLabsPenalty,
      avoidedInstructorsPenalty: avoidedInstructorsPenalty ?? this.avoidedInstructorsPenalty,
      backToBackPenalty: backToBackPenalty ?? this.backToBackPenalty,
      gapsPenalty: gapsPenalty ?? this.gapsPenalty,
      lunchBreakPenalty: lunchBreakPenalty ?? this.lunchBreakPenalty,
      timeOfDayPenalty: timeOfDayPenalty ?? this.timeOfDayPenalty,
      examSpreadPenalty: examSpreadPenalty ?? this.examSpreadPenalty,
      preferredInstructorsBonus: preferredInstructorsBonus ?? this.preferredInstructorsBonus,
      instructorRankingsBonus: instructorRankingsBonus ?? this.instructorRankingsBonus,
      freeDayBonus: freeDayBonus ?? this.freeDayBonus,
      examSlotBonus: examSlotBonus ?? this.examSlotBonus,
      optionalCoursesBonus: optionalCoursesBonus ?? this.optionalCoursesBonus,
    );
  }

  Map<String, dynamic> toJson() => {
    'maxHoursPerDayPenalty': maxHoursPerDayPenalty,
    'avoidTimesPenalty': avoidTimesPenalty,
    'avoidLabsPenalty': avoidLabsPenalty,
    'avoidedInstructorsPenalty': avoidedInstructorsPenalty,
    'backToBackPenalty': backToBackPenalty,
    'gapsPenalty': gapsPenalty,
    'lunchBreakPenalty': lunchBreakPenalty,
    'timeOfDayPenalty': timeOfDayPenalty,
    'examSpreadPenalty': examSpreadPenalty,
    'preferredInstructorsBonus': preferredInstructorsBonus,
    'instructorRankingsBonus': instructorRankingsBonus,
    'freeDayBonus': freeDayBonus,
    'examSlotBonus': examSlotBonus,
    'optionalCoursesBonus': optionalCoursesBonus,
  };

  factory ScoringWeights.fromJson(Map<String, dynamic> json) => ScoringWeights(
    maxHoursPerDayPenalty: (json['maxHoursPerDayPenalty'] as num?)?.toDouble() ?? 15,
    avoidTimesPenalty: (json['avoidTimesPenalty'] as num?)?.toDouble() ?? 15,
    avoidLabsPenalty: (json['avoidLabsPenalty'] as num?)?.toDouble() ?? 10,
    avoidedInstructorsPenalty: (json['avoidedInstructorsPenalty'] as num?)?.toDouble() ?? 15,
    backToBackPenalty: (json['backToBackPenalty'] as num?)?.toDouble() ?? 8,
    gapsPenalty: (json['gapsPenalty'] as num?)?.toDouble() ?? 8,
    lunchBreakPenalty: (json['lunchBreakPenalty'] as num?)?.toDouble() ?? 5,
    timeOfDayPenalty: (json['timeOfDayPenalty'] as num?)?.toDouble() ?? 7,
    examSpreadPenalty: (json['examSpreadPenalty'] as num?)?.toDouble() ?? 7,
    preferredInstructorsBonus: (json['preferredInstructorsBonus'] as num?)?.toDouble() ?? 2,
    instructorRankingsBonus: (json['instructorRankingsBonus'] as num?)?.toDouble() ?? 2,
    freeDayBonus: (json['freeDayBonus'] as num?)?.toDouble() ?? 3,
    examSlotBonus: (json['examSlotBonus'] as num?)?.toDouble() ?? 2,
    optionalCoursesBonus: (json['optionalCoursesBonus'] as num?)?.toDouble() ?? 3,
  );

  double get totalPenaltyCap =>
      maxHoursPerDayPenalty + avoidTimesPenalty + avoidLabsPenalty +
      avoidedInstructorsPenalty + backToBackPenalty + gapsPenalty +
      lunchBreakPenalty + timeOfDayPenalty + examSpreadPenalty;

  double get totalBonusCap =>
      preferredInstructorsBonus + instructorRankingsBonus +
      freeDayBonus + examSlotBonus + optionalCoursesBonus;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoringWeights &&
          maxHoursPerDayPenalty == other.maxHoursPerDayPenalty &&
          avoidTimesPenalty == other.avoidTimesPenalty &&
          avoidLabsPenalty == other.avoidLabsPenalty &&
          avoidedInstructorsPenalty == other.avoidedInstructorsPenalty &&
          backToBackPenalty == other.backToBackPenalty &&
          gapsPenalty == other.gapsPenalty &&
          lunchBreakPenalty == other.lunchBreakPenalty &&
          timeOfDayPenalty == other.timeOfDayPenalty &&
          examSpreadPenalty == other.examSpreadPenalty &&
          preferredInstructorsBonus == other.preferredInstructorsBonus &&
          instructorRankingsBonus == other.instructorRankingsBonus &&
          freeDayBonus == other.freeDayBonus &&
          examSlotBonus == other.examSlotBonus &&
          optionalCoursesBonus == other.optionalCoursesBonus;

  @override
  int get hashCode => Object.hash(
      maxHoursPerDayPenalty, avoidTimesPenalty, avoidLabsPenalty,
      avoidedInstructorsPenalty, backToBackPenalty, gapsPenalty,
      lunchBreakPenalty, timeOfDayPenalty, examSpreadPenalty,
      preferredInstructorsBonus, instructorRankingsBonus,
      freeDayBonus, examSlotBonus, optionalCoursesBonus);
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

enum TimeOfDayPreference {
  none,
  morning,
  afternoon,
}