import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../utils/datetime_utils.dart';
import '../data/campus_service.dart';

/// Detects scheduling conflicts between selected course sections.
///
/// ## Strategy
///
/// **Class clashes** — builds a `Map<"day_hour", List<SelectedSection>>`;
/// any key with >1 entry is a conflict. O(total scheduled slots).
///
/// **Exam clashes** — builds two maps keyed by `"isoDate_timeSlot"`, one for
/// midsems and one for compres. Two courses sharing a key clash.
///
/// ## Hook points
///
/// - To add a new clash type, create a `_detectXxxClashes` method and append
///   its results in [detectClashes].
/// - [canAddSection] is the UI gatekeeper — it must remain fast (called on
///   every section tap). It delegates to [detectClashes] after a trial add.
/// - [checkScheduleConflicts] / [checkExamConflicts] serve the add/swap
///   screen where conflict info is shown per-section rather than globally.
/// - [findSafeCombination] does a cartesian search across section types for
///   one course, returning the first combination with zero conflicts.
class ClashDetector {
  /// Returns all class-time and exam clashes among [selectedSections].
  static List<ClashWarning> detectClashes(List<SelectedSection> selectedSections, List<Course> courses) {
    List<ClashWarning> warnings = [];

    warnings.addAll(_detectRegularClassClashes(selectedSections));
    warnings.addAll(_detectExamClashes(selectedSections, courses));
    return warnings;
  }

  static List<ClashWarning> _detectRegularClassClashes(List<SelectedSection> selectedSections) {
    List<ClashWarning> warnings = [];
    Map<String, List<SelectedSection>> dayHourMap = {};

    for (var selectedSection in selectedSections) {
      // Use the new schedule structure that properly handles day-hour pairings
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          for (var hour in scheduleEntry.hours) {
            String key = '${day.toString()}_$hour';
            dayHourMap[key] ??= [];
            dayHourMap[key]!.add(selectedSection);
          }
        }
      }
    }

    for (var entry in dayHourMap.entries) {
      if (entry.value.length > 1) {
        // Always flag time conflicts, regardless of course
        var conflictingSections = entry.value;
        var dayHour = entry.key.split('_');
        var day = dayHour[0];
        var hour = int.parse(dayHour[1]);

        // Create descriptive message with section details
        var sectionDetails = conflictingSections.map((s) => '${s.courseCode}-${s.sectionId}').join(', ');
        var dayEnum = DayOfWeek.values.firstWhere(
          (d) => d.toString() == day,
          orElse: () => DayOfWeek.M,
        );
        var dayName = getDayName(dayEnum);

        warnings.add(ClashWarning(
          type: ClashType.regularClass,
          message: 'Class time clash on $dayName at ${TimeSlotInfo.getHourSlotName(hour)} between: $sectionDetails',
          conflictingCourses: conflictingSections.map((s) => s.courseCode).toList(),
          severity: ClashSeverity.error,
        ));
      }
    }

    return warnings;
  }

  /// Looks up a course by code, returning null instead of throwing when the
  /// code is not in [courses] (e.g. stale local data after an admin removal).
  static Course? _findCourse(List<Course> courses, String courseCode) {
    for (final c in courses) {
      if (c.courseCode == courseCode) return c;
    }
    return null;
  }

  /// Looks up a section by id within [course], returning null when not found.
  static Section? _findSection(Course course, String sectionId) {
    for (final s in course.sections) {
      if (s.sectionId == sectionId) return s;
    }
    return null;
  }

  static List<ClashWarning> _detectExamClashes(List<SelectedSection> selectedSections, List<Course> courses) {
    List<ClashWarning> warnings = [];

    Map<String, Set<String>> midSemClashes = {};
    Map<String, Set<String>> endSemClashes = {};

    for (var selectedSection in selectedSections) {
      final course = _findCourse(courses, selectedSection.courseCode);
      if (course == null) continue; // Skip unknown course instead of throwing

      if (course.midSemExam != null) {
        String midSemKey = '${course.midSemExam!.date.toIso8601String()}_${course.midSemExam!.timeSlot}';
        midSemClashes[midSemKey] ??= <String>{};
        midSemClashes[midSemKey]!.add(course.courseCode);
      }

      if (course.endSemExam != null) {
        String endSemKey = '${course.endSemExam!.date.toIso8601String()}_${course.endSemExam!.timeSlot}';
        endSemClashes[endSemKey] ??= <String>{};
        endSemClashes[endSemKey]!.add(course.courseCode);
      }
    }

    for (var entry in midSemClashes.entries) {
      if (entry.value.length > 1) {
        var keyParts = entry.key.split('_');
        var date = DateTime.parse(keyParts[0]);
        var timeSlot = TimeSlot.values.firstWhere((e) => e.toString() == keyParts[1]);

        warnings.add(ClashWarning(
          type: ClashType.midSemExam,
          message: 'MidSem exam clash on ${date.day}/${date.month} ${TimeSlotInfo.getTimeSlotName(timeSlot, campus: CampusService.currentCampusCode)}',
          conflictingCourses: entry.value.toList(),
          severity: ClashSeverity.error,
        ));
      }
    }

    for (var entry in endSemClashes.entries) {
      if (entry.value.length > 1) {
        var keyParts = entry.key.split('_');
        var date = DateTime.parse(keyParts[0]);
        var timeSlot = TimeSlot.values.firstWhere((e) => e.toString() == keyParts[1]);

        warnings.add(ClashWarning(
          type: ClashType.endSemExam,
          message: 'EndSem exam clash on ${date.day}/${date.month} ${TimeSlotInfo.getTimeSlotName(timeSlot, campus: CampusService.currentCampusCode)}',
          conflictingCourses: entry.value.toList(),
          severity: ClashSeverity.error,
        ));
      }
    }

    return warnings;
  }

  /// Whether [newSection] can be added without creating any error-level clash.
  /// Enforces one section per type per course, then checks exams, then trial-adds
  /// and runs [detectClashes].
  static bool canAddSection(SelectedSection newSection, List<SelectedSection> currentSections, List<Course> courses) {
    // Check if user is trying to add multiple sections of same type for same course
    final sameCourseTypeSections = currentSections.where(
      (s) => s.courseCode == newSection.courseCode && s.section.type == newSection.section.type
    );

    if (sameCourseTypeSections.isNotEmpty) {
      return false; // Can only have one L, one P, one T per course
    }

    // Check for exam conflicts (only with different courses)
    final newCourse = _findCourse(courses, newSection.courseCode);

    for (var existingSection in currentSections) {
      // Skip exam conflict check if it's the same course
      if (newCourse == null || existingSection.courseCode == newSection.courseCode) {
        continue;
      }

      final existingCourse = _findCourse(courses, existingSection.courseCode);
      if (existingCourse == null) continue; // Skip unknown course

      // Check MidSem exam clash
      if (newCourse.midSemExam != null && existingCourse.midSemExam != null) {
        if (_examTimesConflict(newCourse.midSemExam!, existingCourse.midSemExam!)) {
          return false;
        }
      }

      // Check EndSem exam clash
      if (newCourse.endSemExam != null && existingCourse.endSemExam != null) {
        if (_examTimesConflict(newCourse.endSemExam!, existingCourse.endSemExam!)) {
          return false;
        }
      }
    }

    // Check regular class time clashes
    var tempSections = [...currentSections, newSection];
    var clashes = detectClashes(tempSections, courses);

    return !clashes.any((clash) => clash.severity == ClashSeverity.error);
  }

  static bool _examTimesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    return exam1.date.day == exam2.date.day &&
           exam1.date.month == exam2.date.month &&
           exam1.date.year == exam2.date.year &&
           exam1.timeSlot == exam2.timeSlot;
  }

  // ── Add/Swap screen conflict-detection methods ──────────────────────

  /// Check a single section for schedule conflicts against existing timetable sections.
  static List<ConflictInfo> checkScheduleConflicts(
    Section section,
    List<SelectedSection> currentTimetableSections,
  ) {
    final conflicts = <ConflictInfo>[];

    for (final scheduleEntry in section.schedule) {
      for (final day in scheduleEntry.days) {
        for (final hour in scheduleEntry.hours) {
          for (final currentSelected in currentTimetableSections) {
            for (final currentScheduleEntry in currentSelected.section.schedule) {
              if (currentScheduleEntry.days.contains(day) && currentScheduleEntry.hours.contains(hour)) {
                conflicts.add(ConflictInfo(
                  conflictingCourse: currentSelected.courseCode,
                  conflictingSectionId: currentSelected.sectionId,
                  day: day,
                  time: TimeSlotInfo.getHourSlotName(hour),
                ));
              }
            }
          }
        }
      }
    }

    return conflicts;
  }

  /// Check a course's exams for conflicts against existing timetable sections.
  static List<ConflictInfo> checkExamConflicts(
    Course newCourse,
    List<SelectedSection> currentTimetableSections,
    List<Course> availableCourses,
  ) {
    final conflicts = <ConflictInfo>[];

    // Check for mid-semester exam conflicts
    if (newCourse.midSemExam != null) {
      for (final currentSelected in currentTimetableSections) {
        final currentCourse = _findCourse(availableCourses, currentSelected.courseCode);
        if (currentCourse == null) continue;

        if (currentCourse.midSemExam != null) {
          if (examDatesConflict(newCourse.midSemExam!, currentCourse.midSemExam!)) {
            conflicts.add(ConflictInfo(
              conflictingCourse: currentSelected.courseCode,
              conflictingSectionId: 'Mid-Sem Exam',
              day: DayOfWeek.M,
              time: 'Mid-Sem Exam: ${TimeSlotInfo.getTimeSlotName(newCourse.midSemExam!.timeSlot, campus: CampusService.currentCampusCode)}',
            ));
          }
        }
      }
    }

    // Check for comprehensive exam conflicts
    if (newCourse.endSemExam != null) {
      for (final currentSelected in currentTimetableSections) {
        final currentCourse = _findCourse(availableCourses, currentSelected.courseCode);
        if (currentCourse == null) continue;

        if (currentCourse.endSemExam != null) {
          if (examDatesConflict(newCourse.endSemExam!, currentCourse.endSemExam!)) {
            conflicts.add(ConflictInfo(
              conflictingCourse: currentSelected.courseCode,
              conflictingSectionId: 'Comprehensive Exam',
              day: DayOfWeek.M,
              time: 'Comprehensive Exam: ${TimeSlotInfo.getTimeSlotName(newCourse.endSemExam!.timeSlot, campus: CampusService.currentCampusCode)}',
            ));
          }
        }
      }
    }

    return conflicts;
  }

  /// Check if two exam schedules conflict (same date + overlapping time slots).
  static bool examDatesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    if (exam1.date.year == exam2.date.year &&
        exam1.date.month == exam2.date.month &&
        exam1.date.day == exam2.date.day) {
      return examTimeSlotsOverlap(exam1.timeSlot, exam2.timeSlot);
    }
    return false;
  }

  /// Check if two exam time slots overlap.
  static bool examTimeSlotsOverlap(TimeSlot slot1, TimeSlot slot2) {
    if (slot1 == slot2) return true;

    final midSemSlots = [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4];
    if (midSemSlots.contains(slot1) && midSemSlots.contains(slot2)) {
      return false;
    }

    final compSlots = [TimeSlot.FN, TimeSlot.AN];
    if (compSlots.contains(slot1) && compSlots.contains(slot2)) {
      return false;
    }

    return false;
  }

  /// Check for conflicts between a section and other newly-selected sections.
  static List<ConflictInfo> checkNewSelectionConflicts(
    Section currentSection,
    Course currentCourse,
    String currentCourseCode,
    String currentSectionId,
    List<SelectedSection> allNewlySelected,
    List<Course> availableCourses,
  ) {
    final conflicts = <ConflictInfo>[];

    // Check class schedule conflicts with other newly selected sections
    for (final scheduleEntry in currentSection.schedule) {
      for (final day in scheduleEntry.days) {
        for (final hour in scheduleEntry.hours) {
          for (final otherSelected in allNewlySelected) {
            if (otherSelected.courseCode == currentCourseCode && otherSelected.sectionId == currentSectionId) {
              continue;
            }

            for (final otherScheduleEntry in otherSelected.section.schedule) {
              if (otherScheduleEntry.days.contains(day) && otherScheduleEntry.hours.contains(hour)) {
                conflicts.add(ConflictInfo(
                  conflictingCourse: otherSelected.courseCode,
                  conflictingSectionId: otherSelected.sectionId,
                  day: day,
                  time: TimeSlotInfo.getHourSlotName(hour),
                ));
              }
            }
          }
        }
      }
    }

    // Check exam conflicts with other newly selected courses
    final examConflicts = checkExamConflictsBetweenNewSelections(
      currentCourse, currentCourseCode, allNewlySelected, availableCourses,
    );
    conflicts.addAll(examConflicts);

    return conflicts;
  }

  /// Check exam conflicts between a course and other newly-selected courses.
  static List<ConflictInfo> checkExamConflictsBetweenNewSelections(
    Course currentCourse,
    String currentCourseCode,
    List<SelectedSection> allNewlySelected,
    List<Course> availableCourses,
  ) {
    final conflicts = <ConflictInfo>[];

    final Set<String> otherCourseCodes = allNewlySelected
        .map((s) => s.courseCode)
        .where((code) => code != currentCourseCode)
        .toSet();

    for (final otherCourseCode in otherCourseCodes) {
      final otherCourse = _findCourse(availableCourses, otherCourseCode);
      if (otherCourse == null) continue;

      if (currentCourse.midSemExam != null && otherCourse.midSemExam != null) {
        if (examDatesConflict(currentCourse.midSemExam!, otherCourse.midSemExam!)) {
          conflicts.add(ConflictInfo(
            conflictingCourse: otherCourseCode,
            conflictingSectionId: 'Mid-Sem Exam',
            day: DayOfWeek.M,
            time: 'Mid-Sem Exam: ${TimeSlotInfo.getTimeSlotName(currentCourse.midSemExam!.timeSlot, campus: CampusService.currentCampusCode)}',
          ));
        }
      }

      if (currentCourse.endSemExam != null && otherCourse.endSemExam != null) {
        if (examDatesConflict(currentCourse.endSemExam!, otherCourse.endSemExam!)) {
          conflicts.add(ConflictInfo(
            conflictingCourse: otherCourseCode,
            conflictingSectionId: 'Comprehensive Exam',
            day: DayOfWeek.M,
            time: 'Comprehensive Exam: ${TimeSlotInfo.getTimeSlotName(currentCourse.endSemExam!.timeSlot, campus: CampusService.currentCampusCode)}',
          ));
        }
      }
    }

    return conflicts;
  }

  /// Find a conflict-free section combination for a course, or null if none exists.
  static Map<SectionType, String>? findSafeCombination(
    Course course,
    List<SelectedSection> currentTimetableSections,
    List<Course> availableCourses,
  ) {
    // Group sections by type
    final Map<SectionType, List<Section>> sectionsByType = {};
    for (final section in course.sections) {
      sectionsByType.putIfAbsent(section.type, () => []).add(section);
    }

    final requiredTypes = sectionsByType.keys.toSet();

    final combinations = generateCombinations(sectionsByType, requiredTypes.toList());

    for (final combination in combinations) {
      if (isCombinationSafe(course, combination, currentTimetableSections, availableCourses)) {
        return combination;
      }
    }

    return null;
  }

  /// Generate all cartesian-product combinations of section type -> section ID.
  static List<Map<SectionType, String>> generateCombinations(
    Map<SectionType, List<Section>> sectionsByType,
    List<SectionType> types,
  ) {
    if (types.isEmpty) return [{}];

    final currentType = types.first;
    final remainingTypes = types.sublist(1);
    final sectionsForType = sectionsByType[currentType] ?? [];

    final subCombinations = generateCombinations(sectionsByType, remainingTypes);
    final allCombinations = <Map<SectionType, String>>[];

    for (final section in sectionsForType) {
      for (final subCombination in subCombinations) {
        final newCombination = Map<SectionType, String>.from(subCombination);
        newCombination[currentType] = section.sectionId;
        allCombinations.add(newCombination);
      }
    }

    return allCombinations;
  }

  /// Check whether a particular section combination can be added without conflicts.
  static bool isCombinationSafe(
    Course course,
    Map<SectionType, String> combination,
    List<SelectedSection> currentTimetableSections,
    List<Course> availableCourses,
  ) {
    // Check for conflicts with existing selected sections
    for (final entry in combination.entries) {
      final section = _findSection(course, entry.value);
      if (section == null) return false; // Invalid combination references a missing section

      final classConflicts = checkScheduleConflicts(section, currentTimetableSections);
      if (classConflicts.isNotEmpty) return false;
    }

    // Check exam conflicts with current timetable
    final examConflicts = checkExamConflicts(course, currentTimetableSections, availableCourses);
    if (examConflicts.isNotEmpty) return false;

    // Check for internal conflicts within the combination
    final sectionsInCombination = combination.entries
        .map((entry) => _findSection(course, entry.value))
        .whereType<Section>()
        .toList();

    for (int i = 0; i < sectionsInCombination.length; i++) {
      for (int j = i + 1; j < sectionsInCombination.length; j++) {
        if (sectionsConflict(sectionsInCombination[i], sectionsInCombination[j])) {
          return false;
        }
      }
    }

    return true;
  }

  /// Check whether two sections have any overlapping day+hour.
  static bool sectionsConflict(Section section1, Section section2) {
    for (final schedule1 in section1.schedule) {
      for (final schedule2 in section2.schedule) {
        for (final day1 in schedule1.days) {
          if (schedule2.days.contains(day1)) {
            for (final hour1 in schedule1.hours) {
              if (schedule2.hours.contains(hour1)) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  /// Human-readable name for a SectionType.
  static String getSectionTypeName(SectionType type) {
    switch (type) {
      case SectionType.L:
        return 'Lecture';
      case SectionType.P:
        return 'Practical';
      case SectionType.T:
        return 'Tutorial';
    }
  }
}

// ── Data classes used by add/swap conflict detection ────────────────

/// Pre-add validation result for one section shown in the add/swap UI.
class ValidationResult {
  final String courseCode;
  final String sectionId;
  final SectionType sectionType;
  final String courseTitle;
  final bool canBeAdded;
  final List<ConflictInfo> conflicts;

  ValidationResult({
    required this.courseCode,
    required this.sectionId,
    required this.sectionType,
    required this.courseTitle,
    required this.canBeAdded,
    required this.conflicts,
  });
}

/// Details of a single day+hour or exam conflict between two sections.
class ConflictInfo {
  final String conflictingCourse;
  final String conflictingSectionId;
  final DayOfWeek day;
  final String time;

  ConflictInfo({
    required this.conflictingCourse,
    required this.conflictingSectionId,
    required this.day,
    required this.time,
  });
}

/// A course + its first conflict-free section combination, returned by
/// [ClashDetector.findSafeCombination] for the "add course" flow.
class SafeCourseResult {
  final String courseCode;
  final String courseTitle;
  final Map<SectionType, String> safeCombination;
  final List<String> instructors;
  final List<String> rooms;
  final String scheduleDescription;
  final Course course;

  SafeCourseResult({
    required this.courseCode,
    required this.courseTitle,
    required this.safeCombination,
    required this.instructors,
    required this.rooms,
    required this.scheduleDescription,
    required this.course,
  });
}
