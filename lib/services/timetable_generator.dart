import 'dart:math';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../models/timetable.dart' as timetable;
import 'clash_detector.dart';

class TimetableGenerator {
  static List<GeneratedTimetable> generateTimetables(
    List<Course> availableCourses,
    TimetableConstraints constraints, {
    int maxTimetables = 30,
  }) {
    
    
    final requiredCourses = availableCourses
        .where((course) => constraints.requiredCourses.contains(course.courseCode))
        .toList();

    
    for (final course in requiredCourses) {
      
    }

    if (requiredCourses.length != constraints.requiredCourses.length) {
      
      throw Exception('Some required courses not found in available courses');
    }

    final allCombinations = _generateAllCombinations(requiredCourses);
    
    
    final validTimetables = <GeneratedTimetable>[];

    for (int i = 0; i < allCombinations.length && validTimetables.length < maxTimetables; i++) {
      final combination = allCombinations[i];
      
      if (_isValidCombination(combination, availableCourses)) {
        final score = _scoreTimetable(combination, constraints, requiredCourses);
        final analysis = _analyzeTimetable(combination, constraints, requiredCourses);
        
        validTimetables.add(GeneratedTimetable(
          id: 'timetable_${validTimetables.length + 1}',
          sections: combination,
          score: score,
          pros: analysis['pros'] as List<String>,
          cons: analysis['cons'] as List<String>,
          hoursPerDay: _calculateHoursPerDay(combination),
        ));
      } else {
        if (i < 5) { // Log first few invalid combinations
          
        }
      }
    }

    

    // No fallback - only return conflict-free timetables

    // Sort by score (highest first)
    validTimetables.sort((a, b) => b.score.compareTo(a.score));
    
    return validTimetables.take(maxTimetables).toList();
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
    double bonus = 0;
    double penalty = 0;

    final hoursPerDay = _calculateHoursPerDay(sections);
    final slotsPerDay = _getSlotsPerDay(sections);

    // --- Penalties (max total: 90) ---

    // Exceeding max hours per day: up to 15 pts
    double hoursPenalty = 0;
    for (final hours in hoursPerDay.values) {
      if (hours > constraints.maxHoursPerDay) {
        hoursPenalty += (hours - constraints.maxHoursPerDay) * 5;
      }
    }
    penalty += hoursPenalty.clamp(0, 15);

    // Time conflicts with avoidTimes: up to 15 pts
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
    penalty += timePenalty.clamp(0, 15);

    // Lab conflicts with avoidLabs: up to 10 pts
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
    penalty += labPenalty.clamp(0, 10);

    // Avoided instructors: up to 15 pts
    double avoidedPenalty = 0;
    for (final section in sections) {
      if (constraints.avoidedInstructors.contains(section.section.instructor)) {
        avoidedPenalty += 15;
      }
    }
    penalty += avoidedPenalty.clamp(0, 15);

    // Back-to-back classes: up to 8 pts
    if (constraints.avoidBackToBackClasses) {
      final backToBackCount = _calculateBackToBackPenalty(sections);
      penalty += (backToBackCount * 3.0).clamp(0, 8);
    }

    // Gaps between classes: up to 8 pts
    if (constraints.minimizeGaps) {
      final gapPenalty = _calculateGapPenalty(slotsPerDay);
      penalty += gapPenalty.clamp(0, 8);
    }

    // Lunch break violation (hours 5-6): up to 5 pts
    if (constraints.protectLunchBreak) {
      double lunchPenalty = 0;
      for (final section in sections) {
        for (final entry in section.section.schedule) {
          final lunchHits = entry.hours.where((h) => h == 5 || h == 6).length;
          lunchPenalty += lunchHits * entry.days.length * 1.5;
        }
      }
      penalty += lunchPenalty.clamp(0, 5);
    }

    // Time-of-day mismatch: up to 7 pts
    if (constraints.timeOfDayPreference != TimeOfDayPreference.none) {
      final todPenalty = _calculateTimeOfDayPenalty(sections, constraints.timeOfDayPreference);
      penalty += todPenalty.clamp(0, 7);
    }

    // Exam spread: up to 7 pts
    final examSpreadPenalty = _calculateExamSpreadPenalty(sections, courses);
    penalty += examSpreadPenalty.clamp(0, 7);

    // --- Bonuses (max total: 10) ---

    // Preferred instructors: up to 2 pts
    if (constraints.preferredInstructors.isNotEmpty) {
      final matched = sections
          .where((s) => constraints.preferredInstructors.contains(s.section.instructor))
          .length;
      bonus += (matched / sections.length * 2).clamp(0, 2);
    }

    // Instructor rankings: up to 2 pts
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
        bonus += (rankBonus / ranked).clamp(0, 2);
      }
    }

    // Free day preference / compact schedule: up to 3 pts
    final freeDays = hoursPerDay.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toSet();

    if (constraints.freeDayPreference.isNotEmpty) {
      double fdBonus = 0;
      final total = constraints.freeDayPreference.length;
      for (int i = 0; i < total; i++) {
        if (freeDays.contains(constraints.freeDayPreference[i])) {
          fdBonus += (total - i) / total * 1.5;
        }
      }
      bonus += fdBonus.clamp(0, 3);
    } else {
      final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;
      if (daysWithClasses <= 4) {
        bonus += ((5 - daysWithClasses) * 1.0).clamp(0, 3);
      }
    }

    // Preferred exam slots: up to 3 pts
    final examSlotBonus = _calculateExamSlotBonus(sections, courses, constraints);
    bonus += examSlotBonus.clamp(0, 3);

    final rawScore = 90 - penalty + bonus.clamp(0, 10);
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
    final examDates = <DateTime>[];

    for (final code in courseCodes) {
      final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
        courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
      ));
      if (course.midSemExam != null) examDates.add(course.midSemExam!.date);
      if (course.endSemExam != null) examDates.add(course.endSemExam!.date);
    }

    if (examDates.length < 2) return 0;
    examDates.sort();

    double penalty = 0;
    for (int i = 1; i < examDates.length; i++) {
      final daysDiff = examDates[i].difference(examDates[i - 1]).inDays;
      if (daysDiff == 0) {
        penalty += 4;
      } else if (daysDiff == 1) {
        penalty += 2;
      }
    }
    return penalty;
  }

  static double _calculateExamSlotBonus(List<ConstraintSelectedSection> sections, List<Course> courses, TimetableConstraints constraints) {
    if (constraints.preferredMidsemSlot == null && constraints.preferredCompreSlot == null) return 0;

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

    if (total == 0) return 0;
    return (matched / total) * 3;
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

    // Exam spread
    final courseCodes = sections.map((s) => s.courseCode).toSet();
    final examDates = <DateTime>[];
    for (final code in courseCodes) {
      final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
        courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
      ));
      if (course.midSemExam != null) examDates.add(course.midSemExam!.date);
      if (course.endSemExam != null) examDates.add(course.endSemExam!.date);
    }
    if (examDates.length >= 2) {
      examDates.sort();
      bool sameDay = false;
      bool backToBack = false;
      for (int i = 1; i < examDates.length; i++) {
        final diff = examDates[i].difference(examDates[i - 1]).inDays;
        if (diff == 0) sameDay = true;
        if (diff == 1) backToBack = true;
      }
      if (sameDay) {
        cons.add('Multiple exams on the same day');
      } else if (backToBack) {
        cons.add('Back-to-back exam days');
      } else {
        pros.add('Exams are well-spaced');
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