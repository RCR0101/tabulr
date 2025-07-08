import '../models/course.dart';
import '../models/timetable.dart';

class ClashDetector {
  static List<ClashWarning> detectClashes(List<SelectedSection> selectedSections, List<Course> courses) {
    List<ClashWarning> warnings = [];
    
    warnings.addAll(_detectRegularClassClashes(selectedSections));
    warnings.addAll(_detectExamClashes(selectedSections, courses));
    warnings.addAll(_detectClassExamClashes(selectedSections, courses));
    
    return warnings;
  }

  static List<ClashWarning> _detectRegularClassClashes(List<SelectedSection> selectedSections) {
    List<ClashWarning> warnings = [];
    Map<String, List<SelectedSection>> dayHourMap = {};

    for (var selectedSection in selectedSections) {
      for (var day in selectedSection.section.days) {
        for (var hour in selectedSection.section.hours) {
          String key = '${day.toString()}_$hour';
          dayHourMap[key] ??= [];
          dayHourMap[key]!.add(selectedSection);
        }
      }
    }

    for (var entry in dayHourMap.entries) {
      if (entry.value.length > 1) {
        // Check if the conflicting sections are from different courses
        var uniqueCourses = entry.value.map((s) => s.courseCode).toSet();
        
        if (uniqueCourses.length > 1) {
          // Only flag as clash if sections are from different courses
          var conflictingCourses = entry.value.map((s) => s.courseCode).toList();
          var dayHour = entry.key.split('_');
          var day = dayHour[0];
          var hour = int.parse(dayHour[1]);
          
          warnings.add(ClashWarning(
            type: ClashType.regularClass,
            message: 'Class time clash on $day at ${TimeSlotInfo.getHourSlotName(hour)}',
            conflictingCourses: conflictingCourses,
            severity: ClashSeverity.error,
          ));
        }
      }
    }

    return warnings;
  }

  static List<ClashWarning> _detectExamClashes(List<SelectedSection> selectedSections, List<Course> courses) {
    List<ClashWarning> warnings = [];
    
    Map<String, Set<String>> midSemClashes = {};
    Map<String, Set<String>> endSemClashes = {};

    for (var selectedSection in selectedSections) {
      var course = courses.firstWhere(
        (c) => c.courseCode == selectedSection.courseCode,
        orElse: () => throw Exception('Course not found'),
      );

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
          message: 'MidSem exam clash on ${date.day}/${date.month} ${TimeSlotInfo.getTimeSlotName(timeSlot)}',
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
          message: 'EndSem exam clash on ${date.day}/${date.month} ${TimeSlotInfo.getTimeSlotName(timeSlot)}',
          conflictingCourses: entry.value.toList(),
          severity: ClashSeverity.error,
        ));
      }
    }

    return warnings;
  }

  static List<ClashWarning> _detectClassExamClashes(List<SelectedSection> selectedSections, List<Course> courses) {
    List<ClashWarning> warnings = [];
    
    for (var selectedSection in selectedSections) {
      var course = courses.firstWhere(
        (c) => c.courseCode == selectedSection.courseCode,
        orElse: () => throw Exception('Course not found'),
      );

      for (var otherSelectedSection in selectedSections) {
        if (otherSelectedSection.courseCode == selectedSection.courseCode) continue;
        
        var otherCourse = courses.firstWhere(
          (c) => c.courseCode == otherSelectedSection.courseCode,
          orElse: () => throw Exception('Course not found'),
        );

        if (_checkClassExamConflict(selectedSection, course, otherCourse)) {
          warnings.add(ClashWarning(
            type: ClashType.classAndExam,
            message: 'Class and exam timing conflict between ${selectedSection.courseCode} and ${otherSelectedSection.courseCode}',
            conflictingCourses: [selectedSection.courseCode, otherSelectedSection.courseCode],
            severity: ClashSeverity.warning,
          ));
        }
      }
    }

    return warnings;
  }

  static bool _checkClassExamConflict(SelectedSection selectedSection, Course course, Course otherCourse) {
    return false;
  }

  static bool canAddSection(SelectedSection newSection, List<SelectedSection> currentSections, List<Course> courses) {
    // Check if user is trying to add multiple sections of same type for same course
    final sameCourseTypeSections = currentSections.where(
      (s) => s.courseCode == newSection.courseCode && s.section.type == newSection.section.type
    );
    
    if (sameCourseTypeSections.isNotEmpty) {
      return false; // Can only have one L, one P, one T per course
    }
    
    // Check for exam conflicts (only with different courses)
    final newCourse = courses.firstWhere(
      (c) => c.courseCode == newSection.courseCode,
      orElse: () => throw Exception('Course not found'),
    );
    
    for (var existingSection in currentSections) {
      // Skip exam conflict check if it's the same course
      if (existingSection.courseCode == newSection.courseCode) {
        continue;
      }
      
      final existingCourse = courses.firstWhere(
        (c) => c.courseCode == existingSection.courseCode,
        orElse: () => throw Exception('Course not found'),
      );
      
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
    
    // Debug: Print clashes to understand what's blocking
    if (clashes.any((clash) => clash.severity == ClashSeverity.error)) {
      print('DEBUG: Blocking ${newSection.courseCode} ${newSection.sectionId} due to clashes:');
      for (var clash in clashes.where((c) => c.severity == ClashSeverity.error)) {
        print('  - ${clash.type}: ${clash.message} (${clash.conflictingCourses})');
      }
    }
    
    return !clashes.any((clash) => clash.severity == ClashSeverity.error);
  }

  static bool _examTimesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    return exam1.date.day == exam2.date.day && 
           exam1.date.month == exam2.date.month && 
           exam1.date.year == exam2.date.year &&
           exam1.timeSlot == exam2.timeSlot;
  }
}