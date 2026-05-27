import 'dart:math';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../../models/timetable.dart' as timetable;
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
///    adding optional courses one at a time (best-scoring section combo wins),
///    respecting maxCredits. Multiple orderings of optionals are tried for
///    variety. See [_addOptionalCourses], [_generateOptionalOrderings].
/// 4. **Deduplicate** — a section-key string set prevents identical timetables
///    generated via different orderings.
/// 5. **Score** — base 90, subtract penalties, add bonuses (clamped 0–100).
///    See [_scoreTimetable] for the full breakdown.
/// 6. **Sort & trim** — top [maxTimetables] by score are returned with
///    descriptive names.
///
/// ## Scoring (see [_scoreTimetable])
///
/// **Penalties** (subtracted from 90): maxHoursPerDay exceeded, avoided time
/// slots, avoided lab slots, avoided instructors, back-to-back classes, gaps
/// between classes, lunch-hour classes, time-of-day mismatch, exam spread
/// (back-to-back compres penalized more than midsems).
///
/// **Bonuses** (added, capped per category and overall): preferred instructors,
/// instructor ranking match, free day preference, exam slot preference,
/// optional course inclusion.
///
/// ## Hook points
///
/// - New penalty/bonus: add a calculation in [_scoreTimetable] and mirror in
///   [_analyzeTimetable] for pros/cons text. Add a weight field to
///   `ScoringWeights` in `timetable_constraints.dart`.
/// - New section type: extend the L/P/T branching in
///   [_generateAllCombinations].
class TimetableGenerator {
  /// Entry point. Returns up to [maxTimetables] clash-free, scored timetables.
  static List<GeneratedTimetable> generateTimetables(
    List<Course> availableCourses,
    TimetableConstraints constraints, {
    int maxTimetables = 30,
  }) {
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

    for (int i = 0; i < mandatoryCombos.length; i++) {
      final base = mandatoryCombos[i];
      if (!_isValidCombination(base, allCourses)) continue;

      for (final ordering in optionalOrderings) {
        final result = _addOptionalCourses(
          base, ordering, allCourses, constraints, mandatoryCredits,
        );

        final key = (result.sections.map((s) => '${s.courseCode}:${s.sectionId}').toList()..sort()).join('|');
        if (seen.contains(key)) continue;
        seen.add(key);

        final score = _scoreTimetable(result.sections, constraints, allCourses);
        final analysis = _analyzeTimetable(result.sections, constraints, allCourses);

        if (result.optionalCodes.isNotEmpty) {
          final optNames = result.optionalCodes.join(', ');
          (analysis['pros'] as List<String>).insert(0, 'Includes optionals: $optNames');
        }

        validTimetables.add(GeneratedTimetable(
          id: '',
          sections: result.sections,
          score: score,
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

    validTimetables.sort((a, b) => b.score.compareTo(a.score));
    final results = validTimetables.take(maxTimetables).toList();

    // Assign descriptive names
    for (int i = 0; i < results.length; i++) {
      final tt = results[i];
      results[i] = GeneratedTimetable(
        id: _generateName(tt, i, results.length),
        sections: tt.sections,
        score: tt.score,
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

  static String _generateName(GeneratedTimetable tt, int index, int total) {
    final freeDays = tt.hoursPerDay.entries.where((e) => e.value == 0).map((e) => e.key).toList();
    final daysWithClasses = tt.hoursPerDay.values.where((h) => h > 0).length;
    final maxH = tt.hoursPerDay.values.reduce(max);

    final tags = <String>[];

    if (freeDays.length >= 2) {
      tags.add('${freeDays.length} free days');
    } else if (freeDays.length == 1) {
      const names = {DayOfWeek.M: 'Mon', DayOfWeek.T: 'Tue', DayOfWeek.W: 'Wed', DayOfWeek.Th: 'Thu', DayOfWeek.F: 'Fri', DayOfWeek.S: 'Sat'};
      tags.add('${names[freeDays.first]} off');
    }

    if (maxH <= 4) {
      tags.add('light days');
    } else if (maxH >= 8) {
      tags.add('packed');
    }

    if (tt.optionalCourseCodes.isNotEmpty) {
      tags.add('+${tt.optionalCourseCodes.length} elective${tt.optionalCourseCodes.length > 1 ? 's' : ''}');
    }

    if (tt.score >= 85) {
      tags.add('top pick');
    } else if (daysWithClasses <= 4) {
      tags.add('compact');
    }

    if (tags.isEmpty) tags.add('option ${index + 1}');

    final label = tags.take(2).join(', ');
    final prefix = String.fromCharCode(65 + (index % 26));
    return '$prefix. ${label[0].toUpperCase()}${label.substring(1)}';
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
      if (currentCredits + optCourse.totalCredits > constraints.maxCredits) continue;

      final sectionCombos = _generateAllCombinations([optCourse]);
      List<ConstraintSelectedSection>? bestCombo;
      double bestScore = -1;

      for (final combo in sectionCombos) {
        final candidate = [...current, ...combo];
        if (!_isValidCombination(candidate, allCourses)) continue;

        final score = _scoreTimetable(candidate, constraints, allCourses);
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
      if (combinations.length > 10000) {
        
        combinations = combinations.take(10000).toList();
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

  static double _scoreTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints, List<Course> courses) {
    final w = constraints.scoringWeights;
    double bonus = 0;
    double penalty = 0;

    final hoursPerDay = _calculateHoursPerDay(sections);
    final slotsPerDay = _getSlotsPerDay(sections);

    // --- Penalties ---

    double hoursPenalty = 0;
    for (final hours in hoursPerDay.values) {
      if (hours > constraints.maxHoursPerDay) {
        hoursPenalty += (hours - constraints.maxHoursPerDay) * 5;
      }
    }
    penalty += hoursPenalty.clamp(0, w.maxHoursPerDayPenalty);

    double timePenalty = 0;
    for (final avoidTime in constraints.avoidTimes) {
      for (final section in sections) {
        for (final scheduleEntry in section.section.schedule) {
          if (scheduleEntry.days.contains(avoidTime.day)) {
            timePenalty += scheduleEntry.hours
                .where((hour) => avoidTime.hours.contains(hour))
                .length * 5;
          }
        }
      }
    }
    penalty += timePenalty.clamp(0, w.avoidTimesPenalty);

    double labPenalty = 0;
    for (final avoidLab in constraints.avoidLabs) {
      for (final section in sections) {
        if (section.section.type == SectionType.P) {
          for (final scheduleEntry in section.section.schedule) {
            if (scheduleEntry.days.contains(avoidLab.day)) {
              labPenalty += scheduleEntry.hours
                  .where((hour) => avoidLab.hours.contains(hour))
                  .length * 8;
            }
          }
        }
      }
    }
    penalty += labPenalty.clamp(0, w.avoidLabsPenalty);

    double avoidedPenalty = 0;
    for (final section in sections) {
      if (constraints.avoidedInstructors.contains(section.section.instructor)) {
        avoidedPenalty += 15;
      }
    }
    penalty += avoidedPenalty.clamp(0, w.avoidedInstructorsPenalty);

    if (constraints.avoidBackToBackClasses) {
      final backToBackCount = _calculateBackToBackPenalty(sections);
      penalty += (backToBackCount * 3.0).clamp(0, w.backToBackPenalty);
    }

    if (constraints.minimizeGaps) {
      final gapPenalty = _calculateGapPenalty(slotsPerDay);
      penalty += gapPenalty.clamp(0, w.gapsPenalty);
    }

    if (constraints.protectLunchBreak) {
      double lunchPenalty = 0;
      for (final section in sections) {
        for (final entry in section.section.schedule) {
          final lunchHits = entry.hours.where((h) => h == 5 || h == 6).length;
          lunchPenalty += lunchHits * entry.days.length * 1.5;
        }
      }
      penalty += lunchPenalty.clamp(0, w.lunchBreakPenalty);
    }

    if (constraints.timeOfDayPreference != TimeOfDayPreference.none) {
      final todPenalty = _calculateTimeOfDayPenalty(sections, constraints.timeOfDayPreference);
      penalty += todPenalty.clamp(0, w.timeOfDayPenalty);
    }

    final examSpreadPenalty = _calculateExamSpreadPenalty(sections, courses);
    penalty += examSpreadPenalty.clamp(0, w.examSpreadPenalty);

    // --- Bonuses ---

    if (constraints.preferredInstructors.isNotEmpty) {
      final matched = sections
          .where((s) => constraints.preferredInstructors.contains(s.section.instructor))
          .length;
      bonus += (matched / sections.length * w.preferredInstructorsBonus).clamp(0, w.preferredInstructorsBonus);
    }

    if (constraints.instructorRankings.isNotEmpty) {
      double rankBonus = 0;
      int ranked = 0;
      for (final section in sections) {
        if (constraints.instructorRankings.containsKey(section.courseCode)) {
          final rankings = constraints.instructorRankings[section.courseCode]!;
          final rank = rankings.getInstructorRank(section.section.instructor, section.section.type);
          if (rank > 0) {
            rankBonus += rank;
            ranked++;
          }
        }
      }
      if (ranked > 0) {
        bonus += (rankBonus / ranked).clamp(0, w.instructorRankingsBonus);
      }
    }

    final freeDays = hoursPerDay.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toSet();

    if (constraints.freeDayPreference.isNotEmpty) {
      double fdBonus = 0;
      final total = constraints.freeDayPreference.length;
      for (int i = 0; i < total; i++) {
        if (freeDays.contains(constraints.freeDayPreference[i])) {
          fdBonus += (total - i) / total * (w.freeDayBonus / 2);
        }
      }
      bonus += fdBonus.clamp(0, w.freeDayBonus);
    } else {
      final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;
      if (daysWithClasses <= 4) {
        bonus += ((5 - daysWithClasses) * 1.0).clamp(0, w.freeDayBonus);
      }
    }

    if (constraints.preferredMidsemSlot != null || constraints.preferredCompreSlot != null) {
      final courseCodes = sections.map((s) => s.courseCode).toSet();
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
      if (total > 0) bonus += (matched / total * w.examSlotBonus).clamp(0, w.examSlotBonus);
    }

    final optionalCodes = constraints.optionalCourses.toSet();
    final includedOptionals = sections.map((s) => s.courseCode).toSet().intersection(optionalCodes);
    if (optionalCodes.isNotEmpty) {
      bonus += (includedOptionals.length / optionalCodes.length * w.optionalCoursesBonus).clamp(0, w.optionalCoursesBonus);
    }

    final rawScore = 90 - penalty + bonus.clamp(0, w.totalBonusCap);
    return rawScore.clamp(0, 100);
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

  static double _calculateTimeOfDayPenalty(List<ConstraintSelectedSection> sections, TimeOfDayPreference pref) {
    double mismatch = 0;
    for (final section in sections) {
      for (final entry in section.section.schedule) {
        for (final hour in entry.hours) {
          if (pref == TimeOfDayPreference.morning && hour >= 7) {
            mismatch += 1;
          } else if (pref == TimeOfDayPreference.afternoon && hour <= 4) {
            mismatch += 1;
          }
        }
      }
    }
    return mismatch;
  }

  static double _calculateExamSpreadPenalty(List<ConstraintSelectedSection> sections, List<Course> courses) {
    final courseCodes = sections.map((s) => s.courseCode).toSet();
    final midsemDates = <DateTime>[];
    final compreDates = <DateTime>[];

    for (final code in courseCodes) {
      final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
        courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
      ));
      if (course.midSemExam != null) midsemDates.add(course.midSemExam!.date);
      if (course.endSemExam != null) compreDates.add(course.endSemExam!.date);
    }

    double penalty = 0;

    // Compres: back-to-back is avoidable and costly
    if (compreDates.length >= 2) {
      compreDates.sort();
      for (int i = 1; i < compreDates.length; i++) {
        final daysDiff = compreDates[i].difference(compreDates[i - 1]).inDays;
        if (daysDiff == 0) penalty += 4;
        else if (daysDiff == 1) penalty += 2;
      }
    }

    // Midsems: crammed into one week, back-to-back is common — light penalty
    if (midsemDates.length >= 2) {
      midsemDates.sort();
      for (int i = 1; i < midsemDates.length; i++) {
        final daysDiff = midsemDates[i].difference(midsemDates[i - 1]).inDays;
        if (daysDiff == 0) penalty += 2;
        else if (daysDiff == 1) penalty += 0.5;
      }
    }

    return penalty;
  }



  static int _calculateBackToBackPenalty(List<ConstraintSelectedSection> sections) {
    final timeSlots = <String, List<ConstraintSelectedSection>>{};
    
    for (final section in sections) {
      for (final scheduleEntry in section.section.schedule) {
        for (final day in scheduleEntry.days) {
          for (final hour in scheduleEntry.hours) {
            final key = '${day.toString()}_$hour';
            timeSlots[key] ??= [];
            timeSlots[key]!.add(section);
          }
        }
      }
    }

    int backToBackCount = 0;
    for (final day in DayOfWeek.values) {
      for (int hour = 1; hour <= 9; hour++) {
        final currentKey = '${day.toString()}_$hour';
        final nextKey = '${day.toString()}_${hour + 1}';
        
        if (timeSlots.containsKey(currentKey) && timeSlots.containsKey(nextKey)) {
          backToBackCount++;
        }
      }
    }

    return backToBackCount;
  }

  static Map<String, dynamic> _analyzeTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints, List<Course> courses) {
    final pros = <String>[];
    final cons = <String>[];

    final hoursPerDay = _calculateHoursPerDay(sections);
    final slotsPerDay = _getSlotsPerDay(sections);
    final maxHours = hoursPerDay.values.reduce(max);
    final minHours = hoursPerDay.values.where((h) => h > 0).reduce(min);

    const dayNames = {
      DayOfWeek.M: 'Mon', DayOfWeek.T: 'Tue', DayOfWeek.W: 'Wed',
      DayOfWeek.Th: 'Thu', DayOfWeek.F: 'Fri', DayOfWeek.S: 'Sat',
    };

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
          .map((d) => dayNames[d]!)
          .toList();
      if (matchedFreeDays.isNotEmpty) {
        pros.add('Free on ${matchedFreeDays.join(', ')}');
      }
      final topPref = constraints.freeDayPreference.first;
      if (!freeDays.contains(topPref)) {
        cons.add('${dayNames[topPref]} is not free');
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