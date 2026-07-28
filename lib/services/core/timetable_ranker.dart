import 'dart:math';

import '../../constants/app_constants.dart';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../../utils/datetime_utils.dart';

/// The intent dimensions a timetable is judged on. Kept deliberately small (6)
/// so Pareto tiering stays meaningful — with many objectives almost everything
/// becomes non-dominated ("many-objective" collapse).
///
/// [coursesFitted] is not a shape preference like the others: the student asked
/// for those electives. Without it every other axis rewards *dropping* one — a
/// course you don't take can't crowd a day, sit in a gap, or clash with an exam
/// — so the emptiest week won by construction. It reads as a constant and drops
/// out of the ranking entirely when no optionals were requested.
enum RankAxis { freeDays, lightLoad, timeFit, instructors, examComfort, coursesFitted }

/// How much a given axis matters to the user — the ranker-native replacement
/// for the old per-penalty weight sliders. Feeds the TOPSIS axis weights.
enum AxisImportance { low, normal, high }

extension AxisImportanceWeight on AxisImportance {
  double get multiplier => switch (this) {
        AxisImportance.low => 0.5,
        AxisImportance.normal => 1.0,
        AxisImportance.high => 2.0,
      };

  String get label => switch (this) {
        AxisImportance.low => 'Low',
        AxisImportance.normal => 'Normal',
        AxisImportance.high => 'High',
      };
}

extension RankAxisLabel on RankAxis {
  String get label {
    switch (this) {
      case RankAxis.freeDays:
        return 'Free days';
      case RankAxis.lightLoad:
        return 'Light, compact days';
      case RankAxis.timeFit:
        return 'Preferred hours';
      case RankAxis.instructors:
        return 'Preferred instructors';
      case RankAxis.examComfort:
        return 'Exam spread';
      case RankAxis.coursesFitted:
        return 'Fitting your electives in';
    }
  }

  /// Compact form for inline "relaxes X" chips.
  String get shortLabel {
    switch (this) {
      case RankAxis.freeDays:
        return 'free days';
      case RankAxis.lightLoad:
        return 'light days';
      case RankAxis.timeFit:
        return 'preferred hours';
      case RankAxis.instructors:
        return 'instructors';
      case RankAxis.examComfort:
        return 'exam spread';
      case RankAxis.coursesFitted:
        return 'electives fitted';
    }
  }
}

/// One candidate after ranking: its Pareto [tier] (1 = a best trade-off),
/// TOPSIS [closeness] (0–1, relative to the pool), how well it satisfied each
/// active axis, and the axes where it fell notably short of what the pool could
/// achieve — the raw material for "this option relaxes X".
class RankedTimetable {
  final GeneratedTimetable timetable;
  final int tier;
  final double closeness;
  final Map<RankAxis, double> axisSatisfaction;
  final List<RankAxis> weakAxes;

  RankedTimetable({
    required this.timetable,
    required this.tier,
    required this.closeness,
    required this.axisSatisfaction,
    required this.weakAxes,
  });
}

class RankingResult {
  final List<RankedTimetable> ranked;
  final List<RankAxis> activeAxes;
  final Map<RankAxis, double> axisWeights;

  /// Human-readable "we couldn't fully honour this" notes — the feasibility
  /// discovery the user can't do up front, handed back as diagnosis.
  final List<String> unmetIntents;

  RankingResult({
    required this.ranked,
    required this.activeAxes,
    required this.axisWeights,
    required this.unmetIntents,
  });
}

/// Ranks already-feasible timetables (clash/exam-free — the hard, system-level
/// constraints are enforced upstream by the generator) purely on how well they
/// serve the user's *soft* intent.
///
/// Pipeline: measure each candidate on up to 5 axes → drop axes with no
/// variance across the pool (an intent the data can't distinguish, e.g. no
/// instructor preference set) → min-max normalise the rest to a 0–1 benefit
/// scale (no magic caps) → Pareto non-dominated sort into tiers → break ties
/// within the ordering by TOPSIS closeness to the ideal point.
class TimetableRanker {
  static const _weekdays = {DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F};

  static RankingResult rank(
    List<GeneratedTimetable> candidates,
    TimetableConstraints c,
    List<Course> allCourses, {
    Map<RankAxis, AxisImportance>? importance,
  }) {
    if (candidates.isEmpty) {
      return RankingResult(ranked: const [], activeAxes: const [], axisWeights: const {}, unmetIntents: const []);
    }

    // 1. Raw measurement per axis. Unset intents naturally read as a constant
    //    (0 cost / 0 benefit) and get dropped by the variance filter below.
    final raw = <RankAxis, List<double>>{
      for (final axis in RankAxis.values)
        axis: [for (final tt in candidates) _rawValue(axis, tt, c, allCourses)],
    };

    // 2. Normalise to a 0–1 benefit scale and drop degenerate (no-variance)
    //    axes — they can't separate options and would only dilute the ranking.
    final active = <RankAxis>[];
    final norm = <RankAxis, List<double>>{};
    for (final axis in RankAxis.values) {
      final vals = raw[axis]!;
      final mn = vals.reduce(min);
      final mx = vals.reduce(max);
      if ((mx - mn).abs() < 1e-9) continue;
      active.add(axis);
      norm[axis] = [
        for (final v in vals)
          _isBenefit(axis) ? (v - mn) / (mx - mn) : (mx - v) / (mx - mn),
      ];
    }

    final n = candidates.length;

    if (active.isEmpty) {
      // Every candidate is identical on every axis — nothing to rank on.
      return RankingResult(
        ranked: [
          for (final tt in candidates)
            RankedTimetable(timetable: tt, tier: 1, closeness: 0.5, axisSatisfaction: const {}, weakAxes: const []),
        ],
        activeAxes: const [],
        axisWeights: const {},
        unmetIntents: _unmetIntents(candidates, c, raw, active),
      );
    }

    // 3. Axis weights come straight from the user's per-axis importance
    //    (default Normal = equal say), then normalised to a convex combination.
    final weights = <RankAxis, double>{};
    var wsum = 0.0;
    for (final axis in active) {
      final w = (importance?[axis] ?? AxisImportance.normal).multiplier;
      weights[axis] = w;
      wsum += w;
    }
    for (final axis in active) {
      weights[axis] = weights[axis]! / wsum;
    }

    // 4. Pareto non-dominated sorting into tiers.
    bool dominates(int a, int b) {
      var strictly = false;
      for (final axis in active) {
        final va = norm[axis]![a];
        final vb = norm[axis]![b];
        if (va < vb - 1e-9) return false;
        if (va > vb + 1e-9) strictly = true;
      }
      return strictly;
    }

    final tiers = List<int>.filled(n, 0);
    final assigned = <int>{};
    var tier = 1;
    while (assigned.length < n) {
      final front = <int>[];
      for (var i = 0; i < n; i++) {
        if (assigned.contains(i)) continue;
        var dominated = false;
        for (var j = 0; j < n; j++) {
          if (j == i || assigned.contains(j)) continue;
          if (dominates(j, i)) {
            dominated = true;
            break;
          }
        }
        if (!dominated) front.add(i);
      }
      if (front.isEmpty) break; // safety; shouldn't happen for a valid partial order
      for (final i in front) {
        tiers[i] = tier;
        assigned.add(i);
      }
      tier++;
    }

    // 5. TOPSIS closeness. Ideal point is the weighted max (w) on every axis,
    //    anti-ideal is 0; closeness rewards being near ideal on ALL axes, which
    //    is what makes it less compensatory than a plain weighted sum.
    final closeness = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var dPlus = 0.0;
      var dMinus = 0.0;
      for (final axis in active) {
        final w = weights[axis]!;
        final wv = w * norm[axis]![i];
        dPlus += (wv - w) * (wv - w);
        dMinus += wv * wv;
      }
      dPlus = sqrt(dPlus);
      dMinus = sqrt(dMinus);
      closeness[i] = (dPlus + dMinus) < 1e-9 ? 0.5 : dMinus / (dPlus + dMinus);
    }

    final poolBest = {for (final axis in active) axis: norm[axis]!.reduce(max)};

    final ranked = <RankedTimetable>[];
    for (var i = 0; i < n; i++) {
      final sat = {for (final axis in active) axis: norm[axis]![i]};
      final weak = [
        for (final axis in active)
          if (sat[axis]! < poolBest[axis]! - 0.25) axis,
      ];
      ranked.add(RankedTimetable(
        timetable: candidates[i],
        tier: tiers[i],
        closeness: closeness[i],
        axisSatisfaction: sat,
        weakAxes: weak,
      ));
    }

    ranked.sort((a, b) {
      if (a.tier != b.tier) return a.tier.compareTo(b.tier);
      return b.closeness.compareTo(a.closeness);
    });

    return RankingResult(
      ranked: ranked,
      activeAxes: active,
      axisWeights: weights,
      unmetIntents: _unmetIntents(candidates, c, raw, active),
    );
  }

  // ── Hard constraints (advanced opt-in) ────────────────────────────────────

  /// True when the user has promoted at least one soft intent to a hard filter
  /// (and its underlying intent is actually set).
  static bool hasHardConstraints(TimetableConstraints c) =>
      _hardWindow(c) || _hardFreeDays(c) || _hardLunch(c);

  static bool _hardWindow(TimetableConstraints c) =>
      c.requireHoursWindow && (c.earliestStartSlot != null || c.latestEndSlot != null);
  static bool _hardFreeDays(TimetableConstraints c) =>
      c.requireFreeDays && c.freeDayPreference.isNotEmpty;
  static bool _hardLunch(TimetableConstraints c) =>
      c.requireLunchFree && c.protectLunchBreak;

  /// A candidate passes only if it honours every *required* intent exactly.
  static bool meetsHardConstraints(GeneratedTimetable tt, TimetableConstraints c) {
    if (_hardWindow(c) && !_meetsWindow(tt, c)) return false;
    if (_hardFreeDays(c) && !_meetsFreeDays(tt, c)) return false;
    if (_hardLunch(c) && !_meetsLunch(tt, c)) return false;
    return true;
  }

  static bool _meetsWindow(GeneratedTimetable tt, TimetableConstraints c) {
    for (final s in tt.sections) {
      for (final entry in s.section.schedule) {
        for (final h in entry.hours) {
          if (c.earliestStartSlot != null && h < c.earliestStartSlot!) return false;
          if (c.latestEndSlot != null && h > c.latestEndSlot!) return false;
        }
      }
    }
    return true;
  }

  static bool _meetsFreeDays(GeneratedTimetable tt, TimetableConstraints c) =>
      c.freeDayPreference.every((d) => (tt.hoursPerDay[d] ?? 0) == 0);

  static bool _meetsLunch(GeneratedTimetable tt, TimetableConstraints c) {
    for (final s in tt.sections) {
      for (final entry in s.section.schedule) {
        if (entry.hours.any(ScheduleConstants.lunchHours.contains)) return false;
      }
    }
    return true;
  }

  /// When required constraints leave no candidate, explain *why*: which single
  /// requirement is impossible on its own, or that they only conflict jointly —
  /// so the user knows exactly what to relax.
  static List<String> hardConflictDiagnosis(List<GeneratedTimetable> candidates, TimetableConstraints c) {
    final reqs = <(String, bool Function(GeneratedTimetable))>[
      if (_hardWindow(c)) ('your class-hours window', (tt) => _meetsWindow(tt, c)),
      if (_hardFreeDays(c))
        ('keeping ${c.freeDayPreference.map(getDayName).join(' & ')} free', (tt) => _meetsFreeDays(tt, c)),
      if (_hardLunch(c)) ('a free lunch break', (tt) => _meetsLunch(tt, c)),
    ];
    if (reqs.isEmpty || candidates.isEmpty) return const [];

    final notes = <String>[];
    var anyImpossibleAlone = false;
    for (final (label, pred) in reqs) {
      if (!candidates.any(pred)) {
        notes.add('No clash-free timetable can give you $label — try making it a preference instead.');
        anyImpossibleAlone = true;
      }
    }
    // Each is reachable on its own, but not together.
    if (!anyImpossibleAlone && reqs.length > 1) {
      notes.add('No timetable satisfies all your required constraints at once (${reqs.map((r) => r.$1).join(', ')}). Relax one to a preference.');
    }
    return notes;
  }

  // ── Axis measurement ──────────────────────────────────────────────────────

  static bool _isBenefit(RankAxis axis) =>
      axis == RankAxis.freeDays ||
      axis == RankAxis.instructors ||
      axis == RankAxis.coursesFitted;

  static double _rawValue(RankAxis axis, GeneratedTimetable tt, TimetableConstraints c, List<Course> courses) {
    switch (axis) {
      case RankAxis.freeDays:
        return _freeDaysRaw(tt, c);
      case RankAxis.lightLoad:
        return _loadCost(tt);
      case RankAxis.timeFit:
        return _timeFitCost(tt, c);
      case RankAxis.instructors:
        return _instructorBenefit(tt, c);
      case RankAxis.examComfort:
        return _examCost(tt, courses);
      case RankAxis.coursesFitted:
        return tt.optionalCourseCodes.length.toDouble();
    }
  }

  static double _freeDaysRaw(GeneratedTimetable tt, TimetableConstraints c) {
    final free = _weekdays.where((d) => (tt.hoursPerDay[d] ?? 0) == 0);
    if (c.freeDayPreference.isEmpty) return free.length.toDouble();
    // Weight days the user actually asked to keep free more heavily.
    var s = 0.0;
    for (final d in free) {
      s += c.freeDayPreference.contains(d) ? 2.0 : 1.0;
    }
    return s;
  }

  static double _loadCost(GeneratedTimetable tt) {
    final busiest = tt.hoursPerDay.values.fold(0, max);
    return busiest.toDouble() + _gapCount(_slotsPerDay(tt));
  }

  static double _timeFitCost(GeneratedTimetable tt, TimetableConstraints c) {
    var cost = 0.0;
    for (final s in tt.sections) {
      for (final entry in s.section.schedule) {
        final days = entry.days.length;
        for (final h in entry.hours) {
          if (c.earliestStartSlot != null && h < c.earliestStartSlot!) cost += days;
          if (c.latestEndSlot != null && h > c.latestEndSlot!) cost += days;
          if (c.timeOfDayPreference == TimeOfDayPreference.morning && h >= 7) cost += days;
          if (c.timeOfDayPreference == TimeOfDayPreference.afternoon && h <= 4) cost += days;
          if (c.protectLunchBreak && ScheduleConstants.lunchHours.contains(h)) {
            cost += days;
          }
        }
      }
    }
    return cost;
  }

  static double _instructorBenefit(GeneratedTimetable tt, TimetableConstraints c) {
    var s = 0.0;
    for (final sec in tt.sections) {
      if (c.preferredInstructors.contains(sec.section.instructor)) s += 1;
      final rankings = c.instructorRankings[sec.courseCode];
      if (rankings != null) {
        s += rankings.getInstructorRank(sec.section.instructor, sec.section.type) * 0.5;
      }
    }
    return s;
  }

  static double _examCost(GeneratedTimetable tt, List<Course> courses) {
    final codes = tt.sections.map((s) => s.courseCode).toSet();
    final compres = <DateTime>[];
    final midsems = <DateTime>[];
    for (final code in codes) {
      final course = courses.where((c) => c.courseCode == code).firstOrNull;
      if (course == null) continue;
      if (course.midSemExam != null) midsems.add(course.midSemExam!.date);
      if (course.endSemExam != null) compres.add(course.endSemExam!.date);
    }
    return _spread(compres, sameDay: 4, adjacent: 2) + _spread(midsems, sameDay: 2, adjacent: 0.5);
  }

  static double _spread(List<DateTime> dates, {required double sameDay, required double adjacent}) {
    if (dates.length < 2) return 0;
    final sorted = [...dates]..sort();
    var penalty = 0.0;
    for (var i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;
      if (diff == 0) {
        penalty += sameDay;
      } else if (diff == 1) {
        penalty += adjacent;
      }
    }
    return penalty;
  }

  // ── Diagnosis ─────────────────────────────────────────────────────────────

  static List<String> _unmetIntents(
    List<GeneratedTimetable> candidates,
    TimetableConstraints c,
    Map<RankAxis, List<double>> raw,
    List<RankAxis> active,
  ) {
    final notes = <String>[];

    // A time intent the best candidate still can't fully honour.
    if ((c.earliestStartSlot != null || c.latestEndSlot != null ||
            c.timeOfDayPreference != TimeOfDayPreference.none || c.protectLunchBreak) &&
        raw[RankAxis.timeFit]!.reduce(min) > 0) {
      notes.add('No option fully fits your preferred hours — the closest ones still schedule some classes outside it.');
    }

    // A specific day the user wanted free that no option can keep free.
    for (final d in c.freeDayPreference) {
      final everFree = candidates.any((tt) => (tt.hoursPerDay[d] ?? 0) == 0);
      if (!everFree) notes.add('No option can keep ${getDayName(d)} free.');
    }

    // A preferred instructor that never appears in any feasible timetable.
    for (final instr in c.preferredInstructors) {
      final everPresent = candidates.any((tt) => tt.sections.any((s) => s.section.instructor == instr));
      if (!everPresent) notes.add('$instr isn\'t available in any clash-free option.');
    }

    // Electives the student asked for that nothing could fit. Named
    // individually, because "which one is the problem" is exactly what they
    // need to decide what to swap.
    if (c.optionalCourses.isNotEmpty) {
      final wanted = c.optionalTarget ?? c.optionalCourses.length;
      final bestFitted =
          candidates.map((tt) => tt.optionalCourseCodes.length).reduce(max);
      if (bestFitted < wanted) {
        final neverFitted = [
          for (final code in c.optionalCourses)
            if (!candidates.any((tt) => tt.optionalCourseCodes.contains(code)))
              code,
        ];
        notes.add(neverFitted.isEmpty
            ? 'No option fits all $wanted of your electives — the best manages $bestFitted.'
            : '${neverFitted.join(', ')} ${neverFitted.length == 1 ? "doesn't" : "don't"} fit alongside your core courses in any clash-free option.');
      }
    }

    return notes;
  }

  // ── Slot helpers ──────────────────────────────────────────────────────────

  static Map<DayOfWeek, List<int>> _slotsPerDay(GeneratedTimetable tt) {
    final slots = {for (final d in DayOfWeek.values) d: <int>{}};
    for (final s in tt.sections) {
      for (final entry in s.section.schedule) {
        for (final d in entry.days) {
          slots[d]!.addAll(entry.hours);
        }
      }
    }
    return slots.map((k, v) => MapEntry(k, v.toList()..sort()));
  }

  static double _gapCount(Map<DayOfWeek, List<int>> slotsPerDay) {
    var gaps = 0.0;
    for (final slots in slotsPerDay.values) {
      for (var i = 1; i < slots.length; i++) {
        final g = slots[i] - slots[i - 1] - 1;
        if (g > 0) gaps += g;
      }
    }
    return gaps;
  }
}
