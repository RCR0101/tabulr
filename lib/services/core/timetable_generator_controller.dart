import 'package:flutter/foundation.dart';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../ui/secure_logger.dart';
import 'timetable_generator.dart';
import 'timetable_ranker.dart';

class TimetableGeneratorController extends ChangeNotifier {
  final List<String> mandatoryCourses = [];
  final List<String> optionalCourses = [];
  int? optionalTarget;
  final List<TimeAvoidance> avoidTimes = [];
  final List<LabAvoidance> avoidLabs = [];
  int maxHoursPerDay = 8;
  final List<String> preferredInstructors = [];
  final List<String> avoidedInstructors = [];
  bool avoidBackToBack = false;
  bool minimizeGaps = false;
  bool protectLunchBreak = false;
  int? earliestStartSlot;
  int? latestEndSlot;
  bool requireHoursWindow = false;
  bool requireFreeDays = false;
  bool requireLunchFree = false;
  TimeOfDayPreference timeOfDayPreference = TimeOfDayPreference.none;
  final List<DayOfWeek> freeDayPreference = [];
  TimeSlot? preferredMidsemSlot;
  TimeSlot? preferredCompreSlot;
  final Map<String, InstructorRankings> instructorRankings = {};

  /// Per-axis importance for the ranker's TOPSIS weights. Absent = Normal.
  final Map<RankAxis, AxisImportance> axisImportance = {};

  RankingResult? rankingResult;
  List<RankedTimetable> get rankedTimetables => rankingResult?.ranked ?? const [];
  bool isGenerating = false;

  TimetableConstraints buildConstraints() {
    return TimetableConstraints(
      mandatoryCourses: mandatoryCourses,
      optionalCourses: optionalCourses,
      optionalTarget: optionalTarget,
      avoidTimes: avoidTimes,
      avoidLabs: avoidLabs,
      maxHoursPerDay: maxHoursPerDay,
      preferredInstructors: preferredInstructors,
      avoidedInstructors: avoidedInstructors,
      avoidBackToBackClasses: avoidBackToBack,
      instructorRankings: instructorRankings,
      freeDayPreference: freeDayPreference,
      minimizeGaps: minimizeGaps,
      timeOfDayPreference: timeOfDayPreference,
      protectLunchBreak: protectLunchBreak,
      earliestStartSlot: earliestStartSlot,
      latestEndSlot: latestEndSlot,
      requireHoursWindow: requireHoursWindow,
      requireFreeDays: requireFreeDays,
      requireLunchFree: requireLunchFree,
      preferredMidsemSlot: preferredMidsemSlot,
      preferredCompreSlot: preferredCompreSlot,
    );
  }

  Future<RankingResult> generate(List<Course> availableCourses) async {
    isGenerating = true;
    notifyListeners();

    try {
      final constraints = buildConstraints();
      final timetables = await SecureLogger.measureAsync(
        'timetable_generation',
        () => TimetableGenerator.generateTimetables(
          availableCourses,
          constraints,
          maxTimetables: 30,
        ),
        {
          'mandatory_count': mandatoryCourses.length,
          'optional_count': optionalCourses.length,
        },
      );

      // Advanced hard constraints filter the feasible set before ranking. If
      // they leave nothing, hand back an empty result carrying the conflict
      // diagnosis (reusing the unmetIntents channel) so the UI can explain it.
      var pool = timetables;
      if (TimetableRanker.hasHardConstraints(constraints)) {
        pool = timetables.where((tt) => TimetableRanker.meetsHardConstraints(tt, constraints)).toList();
        if (pool.isEmpty) {
          rankingResult = RankingResult(
            ranked: const [],
            activeAxes: const [],
            axisWeights: const {},
            unmetIntents: TimetableRanker.hardConflictDiagnosis(timetables, constraints),
          );
          isGenerating = false;
          notifyListeners();
          return rankingResult!;
        }
      }

      // Survivors are ordered by intent (Pareto tiers + TOPSIS), not by an
      // opaque linear score. Axis weights come from the user's importance picks.
      rankingResult = TimetableRanker.rank(pool, constraints, availableCourses, importance: axisImportance);
      isGenerating = false;
      notifyListeners();
      return rankingResult!;
    } catch (e) {
      isGenerating = false;
      notifyListeners();
      rethrow;
    }
  }

  void addMandatoryCourse(String courseCode) {
    if (!mandatoryCourses.contains(courseCode)) {
      mandatoryCourses.add(courseCode);
      optionalCourses.remove(courseCode);
      notifyListeners();
    }
  }

  void removeMandatoryCourse(String courseCode) {
    mandatoryCourses.remove(courseCode);
    notifyListeners();
  }

  void addOptionalCourse(String courseCode) {
    if (!optionalCourses.contains(courseCode)) {
      optionalCourses.add(courseCode);
      mandatoryCourses.remove(courseCode);
      notifyListeners();
    }
  }

  void removeOptionalCourse(String courseCode) {
    optionalCourses.remove(courseCode);
    notifyListeners();
  }

  void addTimeAvoidance(TimeAvoidance avoidance) {
    avoidTimes.add(avoidance);
    notifyListeners();
  }

  void removeTimeAvoidance(int index) {
    avoidTimes.removeAt(index);
    notifyListeners();
  }

  void addLabAvoidance(LabAvoidance avoidance) {
    avoidLabs.add(avoidance);
    notifyListeners();
  }

  void removeLabAvoidance(int index) {
    avoidLabs.removeAt(index);
    notifyListeners();
  }

  void toggleFreeDayPreference(DayOfWeek day) {
    if (freeDayPreference.contains(day)) {
      freeDayPreference.remove(day);
    } else {
      freeDayPreference.add(day);
    }
    notifyListeners();
  }

  void reset() {
    mandatoryCourses.clear();
    optionalCourses.clear();
    optionalTarget = null;
    avoidTimes.clear();
    avoidLabs.clear();
    maxHoursPerDay = 8;
    preferredInstructors.clear();
    avoidedInstructors.clear();
    avoidBackToBack = false;
    minimizeGaps = false;
    protectLunchBreak = false;
    earliestStartSlot = null;
    latestEndSlot = null;
    requireHoursWindow = false;
    requireFreeDays = false;
    requireLunchFree = false;
    timeOfDayPreference = TimeOfDayPreference.none;
    freeDayPreference.clear();
    preferredMidsemSlot = null;
    preferredCompreSlot = null;
    instructorRankings.clear();
    axisImportance.clear();
    rankingResult = null;
    isGenerating = false;
    notifyListeners();
  }
}
