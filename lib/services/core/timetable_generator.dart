import 'dart:math';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../../models/timetable.dart' as timetable;
import '../../constants/app_constants.dart';
import '../../utils/datetime_utils.dart';
import 'clash_detector.dart';

/// Generates ranked timetable options from a set of courses and user preferences.
///
/// ## Pipeline
///
/// 1. **Cartesian product** — for each mandatory course, enumerate every valid
///    (L × P × T) section combination. Products are capped at 10 000 to bound
///    memory. See [_generateAllCombinations].
/// 2. **Validate** — reject any combination with a class or exam clash
///    (delegates to [ClashDetector.detectClashes]). See [_isValidCombination].
/// 3. **Greedy optional insertion** — for each surviving mandatory combo, try
///    adding optional courses one at a time (best [_comboFitness] section combo
///    wins), respecting maxCredits. Multiple orderings of optionals are tried
///    for variety. See [_addOptionalCourses], [_generateOptionalOrderings].
/// 4. **Deduplicate** — a section-key string set prevents identical timetables
///    generated via different orderings.
/// 5. **Prune** — the pool is trimmed to [maxTimetables] by [_comboFitness], a
///    cheap internal day-shape heuristic (not user-facing).
/// 6. **Name** — each survivor gets a descriptive name. Ordering the user sees
///    is decided later by `TimetableRanker` (Pareto tiers + TOPSIS), not here.
///
/// ## Hook points
///
/// - New user-facing ranking factor: add an axis to `TimetableRanker`, not here.
/// - New generation-time heuristic: extend [_comboFitness].
/// - New section type: extend the L/P/T branching in
///   [_generateAllCombinations].
class TimetableGenerator {
  /// Entry point. Returns up to [maxTimetables] clash-free, scored timetables.
  /// How many scored candidates to evaluate before handing a frame back to the
  /// event loop. Chosen so a batch stays well under one 60fps frame (~16ms) on
  /// a mid-range phone while keeping the yield overhead negligible.
  static const int _yieldEvery = 128;

  /// Async so the UI can paint between batches. There is no isolate here on
  /// purpose: web has none, and shipping [Course]/[TimetableConstraints] across
  /// an isolate boundary would cost a full copy each way. Cooperative yielding
  /// with `Future.delayed(Duration.zero)` unblocks the UI on web and native
  /// alike — the old fully-synchronous loop froze it for seconds on large
  /// optional sets (up to the 10,000-combination cap × scoring).
  static Future<List<GeneratedTimetable>> generateTimetables(
    List<Course> availableCourses,
    TimetableConstraints constraints, {
    int maxTimetables = 30,
  }) async {
    final mandatoryCourses = availableCourses
        .where((c) => constraints.mandatoryCourses.contains(c.courseCode))
        .toList();

    if (mandatoryCourses.length != constraints.mandatoryCourses.length) {
      throw Exception('Some mandatory courses not found in available courses');
    }

    // Preserve user ranking order for optionals
    final optionalCourses = constraints.optionalCourses
        .map((code) => availableCourses.firstWhere((c) => c.courseCode == code,
            orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [])))
        .where((c) => c.sections.isNotEmpty)
        .toList();

    final mandatoryCombos = _generateAllCombinations(mandatoryCourses);
    final allCourses = [...mandatoryCourses, ...optionalCourses];

    final mandatoryCredits = mandatoryCourses.fold(0.0, (sum, c) => sum + c.totalCredits);

    // Generate multiple optional orderings for variety
    final optionalOrderings = _generateOptionalOrderings(optionalCourses);

    final seen = <String>{};
    final validTimetables = <GeneratedTimetable>[];
    var sinceYield = 0;

    for (int i = 0; i < mandatoryCombos.length; i++) {
      final base = mandatoryCombos[i];
      if (!_isValidCombination(base, allCourses)) continue;

      for (final ordering in optionalOrderings) {
        // Hand a frame back periodically. Counting scored candidates (rather
        // than outer combos) keeps batches even when one combo has many
        // orderings.
        if (++sinceYield >= _yieldEvery) {
          sinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }

        final result = _addOptionalCourses(
          base, ordering, allCourses, constraints, mandatoryCredits,
        );

        final key = (result.sections.map((s) => '${s.courseCode}:${s.sectionId}').toList()..sort()).join('|');
        if (seen.contains(key)) continue;
        seen.add(key);

        final analysis = _analyzeTimetable(result.sections, constraints, allCourses);

        if (result.optionalCodes.isNotEmpty) {
          final optNames = result.optionalCodes.join(', ');
          (analysis['pros'] as List<String>).insert(0, 'Includes optionals: $optNames');
        }

        validTimetables.add(GeneratedTimetable(
          id: '',
          sections: result.sections,
          pros: analysis['pros'] as List<String>,
          cons: analysis['cons'] as List<String>,
          hoursPerDay: _calculateHoursPerDay(result.sections),
          totalCredits: result.totalCredits,
          optionalCourseCodes: result.optionalCodes,
        ));

        if (validTimetables.length >= maxTimetables * 3) break;
      }
      if (validTimetables.length >= maxTimetables * 3) break;
    }

    // Prune the pool with a cheap internal fitness (day-shape, avoided slots /
    // instructors). This is *not* the ranking the user sees — it only decides
    // which candidates advance to the intent-based ranker.
    final scored = [
      for (final t in validTimetables) (t, _comboFitness(t.sections, constraints)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final results = scored.take(maxTimetables).map((e) => e.$1).toList();

    // Assign descriptive names
    final usedLabels = <String>{};
    for (int i = 0; i < results.length; i++) {
      final tt = results[i];
      results[i] = GeneratedTimetable(
        id: _generateName(tt, i, usedLabels),
        sections: tt.sections,
        pros: tt.pros,
        cons: tt.cons,
        hoursPerDay: tt.hoursPerDay,
        totalCredits: tt.totalCredits,
        optionalCourseCodes: tt.optionalCourseCodes,
      );
    }

    return results;
  }

  static List<List<Course>> _generateOptionalOrderings(List<Course> optionals) {
    if (optionals.length <= 1) return [optionals];

    final orderings = <List<Course>>[List.from(optionals)];

    // Add reverse order
    orderings.add(optionals.reversed.toList());

    // Add orderings that skip each optional (to force different subsets)
    for (int skip = 0; skip < optionals.length && skip < 4; skip++) {
      final reordered = <Course>[
        ...optionals.sublist(skip + 1),
        ...optionals.sublist(0, skip + 1),
      ];
      orderings.add(reordered);
    }

    return orderings;
  }

  // Saturday is off for virtually every BITS timetable, so "Sat off" describes
  // nothing and can't tell two options apart. Only Mon–Fri freedom is notable.
  static const _weekdays = {DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F};

  static String _generateName(GeneratedTimetable tt, int index, Set<String> usedLabels) {
    final freeWeekdays = tt.hoursPerDay.entries
        .where((e) => _weekdays.contains(e.key) && e.value == 0)
        .map((e) => e.key)
        .toList();
    final daysWithClasses = tt.hoursPerDay.values.where((h) => h > 0).length;
    final maxH = tt.hoursPerDay.values.fold(0, max);

    // Earliest / latest occupied slot across the week (slot 1 = 8 AM, 6 = 1 PM).
    final allSlots = _getSlotsPerDay(tt.sections).values.expand((s) => s).toList();
    final earliest = allSlots.isEmpty ? 0 : allSlots.reduce(min);
    final latest = allSlots.isEmpty ? 0 : allSlots.reduce(max);

    // Ordered by how distinctive each trait is, so the first two tags carry the
    // most signal. Enough independent axes here that options rarely collide.
    final tags = <String>[];

    if (freeWeekdays.length >= 2) {
      tags.add('$daysWithClasses-day week');
    } else if (freeWeekdays.length == 1) {
      tags.add('${getDayName(freeWeekdays.first, abbreviated: true)} off');
    }

    if (earliest >= 3) {
      tags.add('late starts');
    } else if (earliest >= 2) {
      tags.add('no 8 AMs');
    }

    if (latest > 0 && latest <= 6) {
      tags.add('afternoons free');
    }

    if (maxH > 0 && maxH <= 4) {
      tags.add('light days');
    } else if (maxH >= 8) {
      tags.add('packed');
    }

    if (tt.optionalCourseCodes.isNotEmpty) {
      tags.add('+${tt.optionalCourseCodes.length} elective${tt.optionalCourseCodes.length > 1 ? 's' : ''}');
    }

    if (tags.isEmpty) tags.add('balanced');

    // Prefer a 2-tag descriptor, but widen to 3 (then fall back to "option N")
    // if a shorter label was already handed to an earlier option — no two cards
    // should read the same.
    String label = tags.take(2).join(', ');
    if (usedLabels.contains(label) && tags.length > 2) {
      label = tags.take(3).join(', ');
    }
    if (usedLabels.contains(label)) {
      label = 'option ${index + 1}';
    }
    usedLabels.add(label);

    // No ordering prefix: the ranker (Pareto tier + closeness) owns order now,
    // so the name is a pure descriptor of what the timetable is like.
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  static _OptionalResult _addOptionalCourses(
    List<ConstraintSelectedSection> base,
    List<Course> optionalCourses,
    List<Course> allCourses,
    TimetableConstraints constraints,
    double mandatoryCredits,
  ) {
    var current = List<ConstraintSelectedSection>.from(base);
    double currentCredits = mandatoryCredits;
    final addedCodes = <String>{};

    for (final optCourse in optionalCourses) {
      // "Any N of M": stop once the requested number of optionals is in.
      if (constraints.optionalTarget != null && addedCodes.length >= constraints.optionalTarget!) break;
      if (currentCredits + optCourse.totalCredits > constraints.maxCredits) continue;

      final sectionCombos = _generateAllCombinations([optCourse]);
      List<ConstraintSelectedSection>? bestCombo;
      double bestScore = -1;

      for (final combo in sectionCombos) {
        final candidate = [...current, ...combo];
        if (!_isValidCombination(candidate, allCourses)) continue;

        final score = _comboFitness(candidate, constraints);
        if (score > bestScore) {
          bestScore = score;
          bestCombo = combo;
        }
      }

      if (bestCombo != null) {
        current = [...current, ...bestCombo];
        currentCredits += optCourse.totalCredits;
        addedCodes.add(optCourse.courseCode);
      }
    }

    return _OptionalResult(
      sections: current,
      totalCredits: currentCredits,
      optionalCodes: addedCodes,
    );
  }

  static List<List<ConstraintSelectedSection>> _generateAllCombinations(List<Course> courses) {
    if (courses.isEmpty) return [];

    List<List<ConstraintSelectedSection>> combinations = [[]];

    for (final course in courses) {
      final newCombinations = <List<ConstraintSelectedSection>>[];
      
      // Group sections by type for this course
      final lectureSection = course.sections.where((s) => s.type == SectionType.L).toList();
      final practicalSections = course.sections.where((s) => s.type == SectionType.P).toList();
      final tutorialSections = course.sections.where((s) => s.type == SectionType.T).toList();
      
      

      for (final combination in combinations) {
        // Handle courses with lecture sections
        if (lectureSection.isNotEmpty) {
          for (final lSection in lectureSection) {
            final newCombination = [...combination];
            newCombination.add(ConstraintSelectedSection(
              courseCode: course.courseCode,
              sectionId: lSection.sectionId,
              section: lSection,
            ));

            // Add practical if available
            if (practicalSections.isNotEmpty) {
              for (final pSection in practicalSections) {
                final withPractical = [...newCombination];
                withPractical.add(ConstraintSelectedSection(
                  courseCode: course.courseCode,
                  sectionId: pSection.sectionId,
                  section: pSection,
                ));

                // Add tutorial if available
                if (tutorialSections.isNotEmpty) {
                  for (final tSection in tutorialSections) {
                    final withTutorial = [...withPractical];
                    withTutorial.add(ConstraintSelectedSection(
                      courseCode: course.courseCode,
                      sectionId: tSection.sectionId,
                      section: tSection,
                    ));
                    newCombinations.add(withTutorial);
                  }
                } else {
                  newCombinations.add(withPractical);
                }
              }
            } else if (tutorialSections.isNotEmpty) {
              // Add tutorial without practical
              for (final tSection in tutorialSections) {
                final withTutorial = [...newCombination];
                withTutorial.add(ConstraintSelectedSection(
                  courseCode: course.courseCode,
                  sectionId: tSection.sectionId,
                  section: tSection,
                ));
                newCombinations.add(withTutorial);
              }
            } else {
              // Only lecture
              newCombinations.add(newCombination);
            }
          }
        } else if (practicalSections.isNotEmpty) {
          // Handle practical-only courses (no lecture sections)
          for (final pSection in practicalSections) {
            final newCombination = [...combination];
            newCombination.add(ConstraintSelectedSection(
              courseCode: course.courseCode,
              sectionId: pSection.sectionId,
              section: pSection,
            ));
            newCombinations.add(newCombination);
          }
        }
      }
      
      combinations = newCombinations;
      
      
      // Limit combinations to prevent exponential explosion
      if (combinations.length > AppLimits.combinationCap) {

        combinations = combinations.take(AppLimits.combinationCap).toList();
      }
      
      if (combinations.isEmpty) {
        
        return []; // Return empty if no combinations possible
      }
    }

    
    return combinations;
  }

  static bool _isValidCombination(List<ConstraintSelectedSection> sections, List<Course> courses) {
    // Basic validation - check if sections have valid time slots
    for (final section in sections) {
      if (section.section.days.isEmpty || section.section.hours.isEmpty) {
        return false; // Invalid section with no scheduled time
      }
    }
    
    // Convert to timetable.dart SelectedSection for clash detection
    try {
      final timetableSections = sections.map((s) => timetable.SelectedSection(
        courseCode: s.courseCode,
        sectionId: s.sectionId,
        section: s.section,
      )).toList();
      
      final clashes = ClashDetector.detectClashes(timetableSections, courses);
      // Reject ANY clashes (both warnings and errors) to prevent conflict timetables
      final isValid = clashes.isEmpty;
      
      return isValid;
    } catch (e) {
      
      return false;
    }
  }

  /// Cheap internal fitness used only to pick a section combo and prune the
  /// candidate pool — never shown to the user (the ranker owns what they see).
  /// Higher is better: penalises long days, gaps, avoided slots/instructors,
  /// and out-of-window / lunch classes; rewards preferred instructors.
  static double _comboFitness(List<ConstraintSelectedSection> sections, TimetableConstraints c) {
    final hoursPerDay = _calculateHoursPerDay(sections);
    var penalty = 0.0;
    for (final h in hoursPerDay.values) {
      if (h > c.maxHoursPerDay) penalty += (h - c.maxHoursPerDay) * 5;
    }
    penalty += _calculateGapPenalty(_getSlotsPerDay(sections));

    for (final s in sections) {
      for (final entry in s.section.schedule) {
        final days = entry.days.length;
        for (final h in entry.hours) {
          if (c.earliestStartSlot != null && h < c.earliestStartSlot!) penalty += 3 * days;
          if (c.latestEndSlot != null && h > c.latestEndSlot!) penalty += 3 * days;
          if (c.protectLunchBreak && (h == 5 || h == 6)) penalty += 1.5 * days;
        }
      }
      if (c.avoidedInstructors.contains(s.section.instructor)) penalty += 15;
    }
    for (final avoid in c.avoidTimes) {
      for (final s in sections) {
        for (final entry in s.section.schedule) {
          if (entry.days.contains(avoid.day)) {
            penalty += entry.hours.where((h) => avoid.hours.contains(h)).length * 5;
          }
        }
      }
    }

    var bonus = 0.0;
    for (final s in sections) {
      if (c.preferredInstructors.contains(s.section.instructor)) bonus += 2;
    }
    return bonus - penalty;
  }

  static Map<DayOfWeek, List<int>> _getSlotsPerDay(List<ConstraintSelectedSection> sections) {
    final slots = <DayOfWeek, Set<int>>{};
    for (final day in DayOfWeek.values) {
      slots[day] = {};
    }
    for (final section in sections) {
      for (final entry in section.section.schedule) {
        for (final day in entry.days) {
          slots[day]!.addAll(entry.hours);
        }
      }
    }
    return slots.map((k, v) {
      final sorted = v.toList()..sort();
      return MapEntry(k, sorted);
    });
  }

  static double _calculateGapPenalty(Map<DayOfWeek, List<int>> slotsPerDay) {
    double totalGaps = 0;
    for (final slots in slotsPerDay.values) {
      if (slots.length < 2) continue;
      for (int i = 1; i < slots.length; i++) {
        final gap = slots[i] - slots[i - 1] - 1;
        if (gap > 0) totalGaps += gap;
      }
    }
    return totalGaps * 1.5;
  }

  static Map<String, dynamic> _analyzeTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints, List<Course> courses) {
    final pros = <String>[];
    final cons = <String>[];

    final hoursPerDay = _calculateHoursPerDay(sections);
    final slotsPerDay = _getSlotsPerDay(sections);
    final maxHours = hoursPerDay.values.reduce(max);
    final minHours = hoursPerDay.values.where((h) => h > 0).reduce(min);

    // Schedule distribution
    if (maxHours <= constraints.maxHoursPerDay) {
      pros.add('Within ${constraints.maxHoursPerDay}h/day limit');
    } else {
      cons.add('Exceeds max hours on some days');
    }

    if (maxHours - minHours <= 2) {
      pros.add('Well-balanced daily load');
    }

    // Preferred instructors
    final preferredCount = sections
        .where((s) => constraints.preferredInstructors.contains(s.section.instructor))
        .length;
    if (preferredCount > 0) {
      pros.add('$preferredCount preferred instructor(s)');
    }

    // Time conflicts
    bool hasConflicts = false;
    for (final avoidTime in constraints.avoidTimes) {
      for (final section in sections) {
        for (final scheduleEntry in section.section.schedule) {
          if (scheduleEntry.days.contains(avoidTime.day) &&
              scheduleEntry.hours.any((hour) => avoidTime.hours.contains(hour))) {
            hasConflicts = true;
            break;
          }
        }
        if (hasConflicts) break;
      }
      if (hasConflicts) break;
    }
    if (!hasConflicts && constraints.avoidTimes.isNotEmpty) {
      pros.add('Avoids all blocked time slots');
    } else if (hasConflicts) {
      cons.add('Conflicts with blocked time slots');
    }

    // Lab conflicts
    bool hasLabConflicts = false;
    for (final avoidLab in constraints.avoidLabs) {
      for (final section in sections) {
        if (section.section.type == SectionType.P) {
          for (final scheduleEntry in section.section.schedule) {
            if (scheduleEntry.days.contains(avoidLab.day) &&
                scheduleEntry.hours.any((hour) => avoidLab.hours.contains(hour))) {
              hasLabConflicts = true;
              break;
            }
          }
        }
        if (hasLabConflicts) break;
      }
      if (hasLabConflicts) break;
    }
    if (!hasLabConflicts && constraints.avoidLabs.isNotEmpty) {
      pros.add('Avoids all blocked lab slots');
    } else if (hasLabConflicts) {
      cons.add('Lab conflicts with blocked slots');
    }

    // Free days
    final freeDays = hoursPerDay.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toSet();
    final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;

    if (constraints.freeDayPreference.isNotEmpty) {
      final matchedFreeDays = constraints.freeDayPreference
          .where((d) => freeDays.contains(d))
          .map((d) => getDayName(d, abbreviated: true))
          .toList();
      if (matchedFreeDays.isNotEmpty) {
        pros.add('Free on ${matchedFreeDays.join(', ')}');
      }
      final topPref = constraints.freeDayPreference.first;
      if (!freeDays.contains(topPref)) {
        cons.add('${getDayName(topPref, abbreviated: true)} is not free');
      }
    } else if (daysWithClasses <= 4) {
      pros.add('Compact schedule ($daysWithClasses days)');
    }

    // Gaps
    if (constraints.minimizeGaps) {
      final gapPenalty = _calculateGapPenalty(slotsPerDay);
      if (gapPenalty == 0) {
        pros.add('No idle gaps between classes');
      } else if (gapPenalty > 4) {
        cons.add('Long gaps between classes');
      }
    }

    // Lunch break
    if (constraints.protectLunchBreak) {
      bool lunchFree = true;
      for (final section in sections) {
        for (final entry in section.section.schedule) {
          if (entry.hours.contains(5) || entry.hours.contains(6)) {
            lunchFree = false;
            break;
          }
        }
        if (!lunchFree) break;
      }
      if (lunchFree) {
        pros.add('Lunch break is free');
      } else {
        cons.add('Classes during lunch hours');
      }
    }

    // Time of day
    if (constraints.timeOfDayPreference == TimeOfDayPreference.morning) {
      final lateCount = sections.expand((s) => s.section.schedule)
          .expand((e) => e.hours)
          .where((h) => h >= 7)
          .length;
      if (lateCount == 0) {
        pros.add('All classes in the morning');
      } else {
        cons.add('$lateCount slot(s) in the afternoon');
      }
    } else if (constraints.timeOfDayPreference == TimeOfDayPreference.afternoon) {
      final earlyCount = sections.expand((s) => s.section.schedule)
          .expand((e) => e.hours)
          .where((h) => h <= 4)
          .length;
      if (earlyCount == 0) {
        pros.add('All classes in the afternoon');
      } else {
        cons.add('$earlyCount slot(s) in the morning');
      }
    }

    // Compre exam spread (midsems are too crammed to be useful here)
    final courseCodes = sections.map((s) => s.courseCode).toSet();
    final compreDates = <DateTime>[];
    for (final code in courseCodes) {
      final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
        courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
      ));
      if (course.endSemExam != null) compreDates.add(course.endSemExam!.date);
    }
    if (compreDates.length >= 2) {
      compreDates.sort();
      bool sameDay = false;
      bool backToBack = false;
      for (int i = 1; i < compreDates.length; i++) {
        final diff = compreDates[i].difference(compreDates[i - 1]).inDays;
        if (diff == 0) sameDay = true;
        if (diff == 1) backToBack = true;
      }
      if (sameDay) {
        cons.add('Multiple compres on the same day');
      } else if (backToBack) {
        cons.add('Back-to-back compre days');
      } else {
        pros.add('Compres are well-spaced');
      }
    }

    // Exam slot preference
    if (constraints.preferredMidsemSlot != null || constraints.preferredCompreSlot != null) {
      int matched = 0;
      int total = 0;
      for (final code in courseCodes) {
        final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
          courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
        ));
        if (constraints.preferredMidsemSlot != null && course.midSemExam != null) {
          total++;
          if (course.midSemExam!.timeSlot == constraints.preferredMidsemSlot) matched++;
        }
        if (constraints.preferredCompreSlot != null && course.endSemExam != null) {
          total++;
          if (course.endSemExam!.timeSlot == constraints.preferredCompreSlot) matched++;
        }
      }
      if (total > 0) {
        if (matched == total) {
          pros.add('All exams in preferred slots');
        } else if (matched > 0) {
          pros.add('$matched/$total exams in preferred slots');
        } else {
          cons.add('No exams in preferred slots');
        }
      }
    }

    return {'pros': pros, 'cons': cons};
  }

  static Map<DayOfWeek, int> _calculateHoursPerDay(List<ConstraintSelectedSection> sections) {
    final hoursPerDay = <DayOfWeek, int>{};
    
    for (final day in DayOfWeek.values) {
      hoursPerDay[day] = 0;
    }

    for (final section in sections) {
      for (final scheduleEntry in section.section.schedule) {
        for (final day in scheduleEntry.days) {
          hoursPerDay[day] = hoursPerDay[day]! + scheduleEntry.hours.length;
        }
      }
    }

    return hoursPerDay;
  }
}

class _OptionalResult {
  final List<ConstraintSelectedSection> sections;
  final double totalCredits;
  final Set<String> optionalCodes;

  _OptionalResult({
    required this.sections,
    required this.totalCredits,
    required this.optionalCodes,
  });
}