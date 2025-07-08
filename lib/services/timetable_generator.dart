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
        final score = _scoreTimetable(combination, constraints);
        final analysis = _analyzeTimetable(combination, constraints);
        
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

    

    // If no valid timetables found, try generating some basic ones without strict validation
    if (validTimetables.isEmpty && allCombinations.isNotEmpty) {
      
      for (int i = 0; i < min(5, allCombinations.length); i++) {
        final combination = allCombinations[i];
        final score = _scoreTimetable(combination, constraints);
        final analysis = _analyzeTimetable(combination, constraints);
        
        validTimetables.add(GeneratedTimetable(
          id: 'basic_timetable_${validTimetables.length + 1}',
          sections: combination,
          score: score,
          pros: ['Basic timetable option', ...analysis['pros'] as List<String>],
          cons: ['May have conflicts', ...analysis['cons'] as List<String>],
          hoursPerDay: _calculateHoursPerDay(combination),
        ));
      }
    }

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
        // Must have at least one lecture section
        if (lectureSection.isEmpty) {
          
          continue; // Skip courses without lecture sections
        }
        
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
      final isValid = !clashes.any((clash) => clash.severity == timetable.ClashSeverity.error);
      
      return isValid;
    } catch (e) {
      
      return false;
    }
  }

  static double _scoreTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints) {
    double score = 100.0; // Base score

    final hoursPerDay = _calculateHoursPerDay(sections);
    
    // Penalty for exceeding max hours per day
    for (final hours in hoursPerDay.values) {
      if (hours > constraints.maxHoursPerDay) {
        score -= (hours - constraints.maxHoursPerDay) * 10;
      }
    }

    // Penalty for time conflicts with avoidTimes
    for (final avoidTime in constraints.avoidTimes) {
      for (final section in sections) {
        for (final scheduleEntry in section.section.schedule) {
          if (scheduleEntry.days.contains(avoidTime.day)) {
            final conflictingHours = scheduleEntry.hours
                .where((hour) => avoidTime.hours.contains(hour))
                .length;
            score -= conflictingHours * 15;
          }
        }
      }
    }

    // Bonus for preferred instructors
    for (final section in sections) {
      if (constraints.preferredInstructors.contains(section.section.instructor)) {
        score += 5;
      }
    }

    // Heavy penalty for avoided instructors
    for (final section in sections) {
      if (constraints.avoidedInstructors.contains(section.section.instructor)) {
        score -= 50; // Heavy penalty to strongly discourage avoided instructors
      }
    }

    // Bonus for avoiding back-to-back classes
    if (constraints.avoidBackToBackClasses) {
      final backToBackPenalty = _calculateBackToBackPenalty(sections);
      score -= backToBackPenalty * 8;
    }

    // Bonus for compact schedule (fewer days with classes)
    final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;
    if (daysWithClasses <= 4) {
      score += (5 - daysWithClasses) * 3;
    }

    return max(0, score);
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

  static Map<String, dynamic> _analyzeTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints) {
    final pros = <String>[];
    final cons = <String>[];
    
    final hoursPerDay = _calculateHoursPerDay(sections);
    final maxHours = hoursPerDay.values.reduce(max);
    final minHours = hoursPerDay.values.where((h) => h > 0).reduce(min);
    
    // Analyze schedule distribution
    if (maxHours <= constraints.maxHoursPerDay) {
      pros.add('Stays within max hours per day limit');
    } else {
      cons.add('Exceeds max hours per day on some days');
    }

    if (maxHours - minHours <= 2) {
      pros.add('Well-balanced daily schedule');
    }

    // Check for preferred instructors
    final preferredCount = sections
        .where((s) => constraints.preferredInstructors.contains(s.section.instructor))
        .length;
    if (preferredCount > 0) {
      pros.add('Includes $preferredCount preferred instructor(s)');
    }

    // Check for time conflicts
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
      pros.add('Avoids all specified time conflicts');
    } else if (hasConflicts) {
      cons.add('Has some time conflicts with preferences');
    }

    // Analyze compactness
    final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;
    if (daysWithClasses <= 4) {
      pros.add('Compact schedule ($daysWithClasses days)');
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