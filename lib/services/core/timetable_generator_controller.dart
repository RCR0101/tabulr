import 'package:flutter/foundation.dart';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../ui/secure_logger.dart';
import 'timetable_generator.dart';
import 'timetable_ranker.dart';

/// Holds everything the generator form collects, and runs the generation.
///
/// State lives here rather than in the widget's `State` so the UI can subscribe
/// at whatever granularity it needs. Collections are handed out as unmodifiable
/// views and every field is written through a mutator: the widget used to hold
/// `_ctrl.optionalCourses.remove(code)` inside a `setState`, which changed the
/// data behind the notifier's back and left correctness depending on whichever
/// `setState` happened to run next. An unmodifiable view makes that a compile
/// error instead of a subtle one.
///
/// Setters no-op when the value is unchanged, so a rebuild only happens when
/// something actually moved.
///
/// Listeners can subscribe either to the whole controller or to one [slice].
/// Slices exist because panel-level subscription is still too coarse: the
/// course search carries a typeahead overlay and its own text controller, and
/// nothing about it changes when a constraint checkbox moves.
class TimetableGeneratorController extends ChangeNotifier {
  /// Narrow subscriptions, so a panel only rebuilds for the state it reads.
  final ChangeNotifier courses = _Slice();
  final ChangeNotifier constraints = _Slice();
  final ChangeNotifier importance = _Slice();
  final ChangeNotifier results = _Slice();

  /// Notifies the whole-controller listeners plus each affected slice.
  void _changed(List<ChangeNotifier> slices) {
    for (final slice in slices) {
      (slice as _Slice).fire();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final slice in [courses, constraints, importance, results]) {
      slice.dispose();
    }
    super.dispose();
  }

  final List<String> _mandatoryCourses = [];
  final List<String> _optionalCourses = [];
  final List<TimeAvoidance> _avoidTimes = [];
  final List<LabAvoidance> _avoidLabs = [];
  final List<String> _preferredInstructors = [];
  final List<String> _avoidedInstructors = [];
  final List<DayOfWeek> _freeDayPreference = [];
  final Map<String, InstructorRankings> _instructorRankings = {};
  final Map<RankAxis, AxisImportance> _axisImportance = {};

  List<String> get mandatoryCourses => List.unmodifiable(_mandatoryCourses);
  List<String> get optionalCourses => List.unmodifiable(_optionalCourses);
  List<TimeAvoidance> get avoidTimes => List.unmodifiable(_avoidTimes);
  List<LabAvoidance> get avoidLabs => List.unmodifiable(_avoidLabs);
  List<String> get preferredInstructors => List.unmodifiable(_preferredInstructors);
  List<String> get avoidedInstructors => List.unmodifiable(_avoidedInstructors);
  List<DayOfWeek> get freeDayPreference => List.unmodifiable(_freeDayPreference);
  Map<String, InstructorRankings> get instructorRankings =>
      Map.unmodifiable(_instructorRankings);

  /// Per-axis importance for the ranker's TOPSIS weights. Absent = Normal.
  Map<RankAxis, AxisImportance> get axisImportance =>
      Map.unmodifiable(_axisImportance);

  int? _optionalTarget;
  int _maxHoursPerDay = 8;
  bool _avoidBackToBack = false;
  bool _minimizeGaps = false;
  bool _protectLunchBreak = false;
  int? _earliestStartSlot;
  int? _latestEndSlot;
  bool _requireHoursWindow = false;
  bool _requireFreeDays = false;
  bool _requireLunchFree = false;
  TimeOfDayPreference _timeOfDayPreference = TimeOfDayPreference.none;
  TimeSlot? _preferredMidsemSlot;
  TimeSlot? _preferredCompreSlot;

  /// "Any N of M electives". Clamped to the number of optionals actually
  /// selected — removing optionals used to leave a stale target that the widget
  /// fixed up mid-`build`, mutating state during a paint.
  int? get optionalTarget {
    final t = _optionalTarget;
    if (t == null) return null;
    return _optionalCourses.isEmpty ? null : t.clamp(1, _optionalCourses.length);
  }

  set optionalTarget(int? value) {
    if (_optionalTarget == value) return;
    _optionalTarget = value;
    _changed([courses]);
  }

  int get maxHoursPerDay => _maxHoursPerDay;
  set maxHoursPerDay(int value) {
    if (_maxHoursPerDay == value) return;
    _maxHoursPerDay = value;
    _changed([constraints]);
  }

  bool get avoidBackToBack => _avoidBackToBack;
  set avoidBackToBack(bool value) {
    if (_avoidBackToBack == value) return;
    _avoidBackToBack = value;
    _changed([constraints]);
  }

  bool get minimizeGaps => _minimizeGaps;
  set minimizeGaps(bool value) {
    if (_minimizeGaps == value) return;
    _minimizeGaps = value;
    _changed([constraints]);
  }

  /// Turning lunch protection off also drops its "require" escalation — a hard
  /// filter on a preference that is no longer expressed would silently return
  /// nothing.
  bool get protectLunchBreak => _protectLunchBreak;
  set protectLunchBreak(bool value) {
    if (_protectLunchBreak == value) return;
    _protectLunchBreak = value;
    if (!value) _requireLunchFree = false;
    _changed([constraints]);
  }

  bool get requireLunchFree => _requireLunchFree;
  set requireLunchFree(bool value) {
    if (_requireLunchFree == value) return;
    _requireLunchFree = value;
    _changed([constraints]);
  }

  int? get earliestStartSlot => _earliestStartSlot;
  set earliestStartSlot(int? value) {
    if (_earliestStartSlot == value) return;
    _earliestStartSlot = value;
    _syncHoursWindowRequirement();
    _changed([constraints]);
  }

  int? get latestEndSlot => _latestEndSlot;
  set latestEndSlot(int? value) {
    if (_latestEndSlot == value) return;
    _latestEndSlot = value;
    _syncHoursWindowRequirement();
    _changed([constraints]);
  }

  bool get hasHoursWindow =>
      _earliestStartSlot != null || _latestEndSlot != null;

  void _syncHoursWindowRequirement() {
    if (!hasHoursWindow) _requireHoursWindow = false;
  }

  /// Sets both ends of the class-hours window in one notification. A full 1–12
  /// range means "no bound", which is represented as nulls.
  void setHoursWindow({required int startSlot, required int endSlot}) {
    final start = startSlot <= 1 ? null : startSlot;
    final end = endSlot >= 12 ? null : endSlot;
    if (_earliestStartSlot == start && _latestEndSlot == end) return;
    _earliestStartSlot = start;
    _latestEndSlot = end;
    _syncHoursWindowRequirement();
    _changed([constraints]);
  }

  void clearHoursWindow() {
    if (!hasHoursWindow && !_requireHoursWindow) return;
    _earliestStartSlot = null;
    _latestEndSlot = null;
    _requireHoursWindow = false;
    _changed([constraints]);
  }

  bool get requireHoursWindow => _requireHoursWindow;
  set requireHoursWindow(bool value) {
    if (_requireHoursWindow == value) return;
    _requireHoursWindow = value;
    _changed([constraints]);
  }

  bool get requireFreeDays => _requireFreeDays;
  set requireFreeDays(bool value) {
    if (_requireFreeDays == value) return;
    _requireFreeDays = value;
    _changed([constraints]);
  }

  TimeOfDayPreference get timeOfDayPreference => _timeOfDayPreference;
  set timeOfDayPreference(TimeOfDayPreference value) {
    if (_timeOfDayPreference == value) return;
    _timeOfDayPreference = value;
    _changed([constraints]);
  }

  TimeSlot? get preferredMidsemSlot => _preferredMidsemSlot;
  set preferredMidsemSlot(TimeSlot? value) {
    if (_preferredMidsemSlot == value) return;
    _preferredMidsemSlot = value;
    _changed([constraints]);
  }

  TimeSlot? get preferredCompreSlot => _preferredCompreSlot;
  set preferredCompreSlot(TimeSlot? value) {
    if (_preferredCompreSlot == value) return;
    _preferredCompreSlot = value;
    _changed([constraints]);
  }

  RankingResult? rankingResult;
  List<RankedTimetable> get rankedTimetables => rankingResult?.ranked ?? const [];
  bool isGenerating = false;

  /// What generated timetables are counted in. Set from the screen's toggle.
  CreditBasis creditBasis = CreditBasis.units;

  void setCreditBasis(CreditBasis basis) {
    if (creditBasis == basis) return;
    creditBasis = basis;
    // Courses of the other basis can no longer be part of this run. Cleared
    // through the private lists: the getters hand out unmodifiable views, so
    // clearing those threw and the toggle never actually switched.
    _mandatoryCourses.clear();
    _optionalCourses.clear();
    _changed([courses, constraints]);
  }

  /// Empties one of the two course lists.
  void clearCourses({required bool mandatory}) {
    final list = mandatory ? _mandatoryCourses : _optionalCourses;
    if (list.isEmpty) return;
    list.clear();
    _changed([courses]);
  }

  TimetableConstraints buildConstraints() {
    return TimetableConstraints(
      creditBasis: creditBasis,
      mandatoryCourses: mandatoryCourses,
      optionalCourses: optionalCourses,
      optionalTarget: optionalTarget,
      avoidTimes: avoidTimes,
      avoidLabs: avoidLabs,
      maxHoursPerDay: _maxHoursPerDay,
      preferredInstructors: preferredInstructors,
      avoidedInstructors: avoidedInstructors,
      avoidBackToBackClasses: _avoidBackToBack,
      instructorRankings: instructorRankings,
      freeDayPreference: freeDayPreference,
      minimizeGaps: _minimizeGaps,
      timeOfDayPreference: _timeOfDayPreference,
      protectLunchBreak: _protectLunchBreak,
      earliestStartSlot: _earliestStartSlot,
      latestEndSlot: _latestEndSlot,
      requireHoursWindow: _requireHoursWindow,
      requireFreeDays: _requireFreeDays,
      requireLunchFree: _requireLunchFree,
      preferredMidsemSlot: _preferredMidsemSlot,
      preferredCompreSlot: _preferredCompreSlot,
    );
  }

  Future<RankingResult> generate(List<Course> availableCourses) async {
    isGenerating = true;
    _changed([results]);

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
          'mandatory_count': _mandatoryCourses.length,
          'optional_count': _optionalCourses.length,
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
          _changed([results]);
          return rankingResult!;
        }
      }

      // Survivors are ordered by intent (Pareto tiers + TOPSIS), not by an
      // opaque linear score. Axis weights come from the user's importance picks.
      rankingResult = TimetableRanker.rank(pool, constraints, availableCourses, importance: _axisImportance);
      isGenerating = false;
      _changed([results]);
      return rankingResult!;
    } catch (e) {
      isGenerating = false;
      _changed([results]);
      rethrow;
    }
  }

  // ── Courses ────────────────────────────────────────────────────────────────

  void addMandatoryCourse(String courseCode) {
    if (_mandatoryCourses.contains(courseCode)) return;
    _mandatoryCourses.add(courseCode);
    _optionalCourses.remove(courseCode);
    _changed([courses]);
  }

  void removeMandatoryCourse(String courseCode) {
    if (!_mandatoryCourses.remove(courseCode)) return;
    _changed([courses]);
  }

  void addOptionalCourse(String courseCode) {
    if (_optionalCourses.contains(courseCode) ||
        _mandatoryCourses.contains(courseCode)) {
      return;
    }
    _optionalCourses.add(courseCode);
    _changed([courses]);
  }

  void removeOptionalCourse(String courseCode) {
    if (!_optionalCourses.remove(courseCode)) return;
    _changed([courses]);
  }

  /// Promotes a batch of codes to mandatory (the auto-CDC path). Returns how
  /// many were newly added, and notifies once rather than per course.
  int addMandatoryCourses(Iterable<String> courseCodes) {
    var added = 0;
    var changed = false;
    for (final code in courseCodes) {
      // A promotion out of the optional list is a change even when the code is
      // already mandatory, so `added` alone can't decide whether to notify.
      if (_optionalCourses.remove(code)) changed = true;
      if (!_mandatoryCourses.contains(code)) {
        _mandatoryCourses.add(code);
        added++;
        changed = true;
      }
    }
    if (changed) _changed([courses]);
    return added;
  }

  /// Reorders one optional course, expressed in whole-list indices. Priority
  /// within a clash cluster is just its order in this list.
  void moveOptionalCourse(String courseCode, {required String beforeCode}) {
    final from = _optionalCourses.indexOf(courseCode);
    final to = _optionalCourses.indexOf(beforeCode);
    if (from < 0 || to < 0 || from == to) return;
    _optionalCourses.insert(to, _optionalCourses.removeAt(from));
    _changed([courses]);
  }

  // ── Avoidance lists ────────────────────────────────────────────────────────

  /// Merges into the existing entry for that day so there is one chip per day.
  void addTimeAvoidance(TimeAvoidance avoidance) {
    final idx = _avoidTimes.indexWhere((a) => a.day == avoidance.day);
    if (idx >= 0) {
      final merged = {..._avoidTimes[idx].hours, ...avoidance.hours}.toList()..sort();
      _avoidTimes[idx] = TimeAvoidance(day: avoidance.day, hours: merged);
    } else {
      _avoidTimes.add(avoidance);
    }
    _changed([constraints]);
  }

  void removeTimeAvoidance(int index) {
    if (index < 0 || index >= _avoidTimes.length) return;
    _avoidTimes.removeAt(index);
    _changed([constraints]);
  }

  void addLabAvoidance(LabAvoidance avoidance) {
    final idx = _avoidLabs.indexWhere((a) => a.day == avoidance.day);
    if (idx >= 0) {
      final merged = {..._avoidLabs[idx].hours, ...avoidance.hours}.toList()..sort();
      _avoidLabs[idx] = LabAvoidance(day: avoidance.day, hours: merged);
    } else {
      _avoidLabs.add(avoidance);
    }
    _changed([constraints]);
  }

  void removeLabAvoidance(int index) {
    if (index < 0 || index >= _avoidLabs.length) return;
    _avoidLabs.removeAt(index);
    _changed([constraints]);
  }

  void addAvoidedInstructors(Iterable<String> instructors) {
    var changed = false;
    for (final instructor in instructors) {
      if (!_avoidedInstructors.contains(instructor)) {
        _avoidedInstructors.add(instructor);
        changed = true;
      }
    }
    if (changed) _changed([constraints]);
  }

  void removeAvoidedInstructor(int index) {
    if (index < 0 || index >= _avoidedInstructors.length) return;
    _avoidedInstructors.removeAt(index);
    _changed([constraints]);
  }

  void setInstructorRankings(Map<String, InstructorRankings> rankings) {
    _instructorRankings
      ..clear()
      ..addAll(rankings);
    _changed([constraints]);
  }

  // ── Free days ──────────────────────────────────────────────────────────────

  void toggleFreeDayPreference(DayOfWeek day) {
    if (!_freeDayPreference.remove(day)) _freeDayPreference.add(day);
    if (_freeDayPreference.isEmpty) _requireFreeDays = false;
    _changed([constraints]);
  }

  void removeFreeDayPreference(DayOfWeek day) {
    if (!_freeDayPreference.remove(day)) return;
    if (_freeDayPreference.isEmpty) _requireFreeDays = false;
    _changed([constraints]);
  }

  void reorderFreeDayPreference(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _freeDayPreference.length) return;
    _freeDayPreference.insert(newIndex, _freeDayPreference.removeAt(oldIndex));
    _changed([constraints]);
  }

  void clearFreeDayPreference() {
    if (_freeDayPreference.isEmpty) return;
    _freeDayPreference.clear();
    _requireFreeDays = false;
    _changed([constraints]);
  }

  // ── Ranking importance ─────────────────────────────────────────────────────

  /// A null [value] removes the override, putting the axis back to its implicit
  /// Normal. The refine chips need that to undo themselves.
  void setAxisImportance(RankAxis axis, AxisImportance? value) {
    if (value == null) {
      if (_axisImportance.remove(axis) != null) _changed([importance]);
      return;
    }
    if (_axisImportance[axis] == value) return;
    _axisImportance[axis] = value;
    _changed([importance]);
  }

  void clearAxisImportance() {
    if (_axisImportance.isEmpty) return;
    _axisImportance.clear();
    _changed([importance]);
  }

  bool get hasCustomImportance =>
      _axisImportance.values.any((v) => v != AxisImportance.normal);

  void reset() {
    _mandatoryCourses.clear();
    _optionalCourses.clear();
    _optionalTarget = null;
    _avoidTimes.clear();
    _avoidLabs.clear();
    _maxHoursPerDay = 8;
    _preferredInstructors.clear();
    _avoidedInstructors.clear();
    _avoidBackToBack = false;
    _minimizeGaps = false;
    _protectLunchBreak = false;
    _earliestStartSlot = null;
    _latestEndSlot = null;
    _requireHoursWindow = false;
    _requireFreeDays = false;
    _requireLunchFree = false;
    _timeOfDayPreference = TimeOfDayPreference.none;
    _freeDayPreference.clear();
    _preferredMidsemSlot = null;
    _preferredCompreSlot = null;
    _instructorRankings.clear();
    _axisImportance.clear();
    rankingResult = null;
    isGenerating = false;
    _changed([courses, constraints, importance, results]);
  }
}

/// A [ChangeNotifier] whose notification is triggered by its owner. Exists so
/// the controller can hand out narrow subscriptions without exposing a way for
/// anyone else to fire them.
class _Slice extends ChangeNotifier {
  void fire() => notifyListeners();
}
