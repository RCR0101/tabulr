import 'package:flutter/foundation.dart';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../ui/secure_logger.dart';
import 'timetable_generator.dart';

class TimetableGeneratorController extends ChangeNotifier {
  final List<String> mandatoryCourses = [];
  final List<String> optionalCourses = [];
  final List<TimeAvoidance> avoidTimes = [];
  final List<LabAvoidance> avoidLabs = [];
  int maxHoursPerDay = 8;
  final List<String> preferredInstructors = [];
  final List<String> avoidedInstructors = [];
  bool avoidBackToBack = false;
  bool minimizeGaps = false;
  bool protectLunchBreak = false;
  TimeOfDayPreference timeOfDayPreference = TimeOfDayPreference.none;
  final List<DayOfWeek> freeDayPreference = [];
  TimeSlot? preferredMidsemSlot;
  TimeSlot? preferredCompreSlot;
  final Map<String, InstructorRankings> instructorRankings = {};
  ScoringWeights scoringWeights = const ScoringWeights();
  ScoringWeights savedScoringWeights = const ScoringWeights();

  List<GeneratedTimetable> generatedTimetables = [];
  bool isGenerating = false;

  TimetableConstraints buildConstraints() {
    return TimetableConstraints(
      mandatoryCourses: mandatoryCourses,
      optionalCourses: optionalCourses,
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
      preferredMidsemSlot: preferredMidsemSlot,
      preferredCompreSlot: preferredCompreSlot,
      scoringWeights: scoringWeights,
    );
  }

  Future<List<GeneratedTimetable>> generate(List<Course> availableCourses) async {
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

      generatedTimetables = timetables;
      isGenerating = false;
      notifyListeners();
      return timetables;
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
    avoidTimes.clear();
    avoidLabs.clear();
    maxHoursPerDay = 8;
    preferredInstructors.clear();
    avoidedInstructors.clear();
    avoidBackToBack = false;
    minimizeGaps = false;
    protectLunchBreak = false;
    timeOfDayPreference = TimeOfDayPreference.none;
    freeDayPreference.clear();
    preferredMidsemSlot = null;
    preferredCompreSlot = null;
    instructorRankings.clear();
    scoringWeights = const ScoringWeights();
    generatedTimetables = [];
    isGenerating = false;
    notifyListeners();
  }
}
