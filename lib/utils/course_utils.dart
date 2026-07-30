import '../models/course.dart';

class CourseUtils {
  static String getInstructorInCharge(Course course) {
    // Check all instructors in all sections, including comma-separated ones
    for (var section in course.sections) {
      final instructorField = section.instructor.trim();
      if (instructorField.isNotEmpty) {
        // Split by comma in case there are multiple instructors
        final instructors = instructorField.split(',').map((i) => i.trim()).toList();
        
        for (var instructor in instructors) {
          if (instructor.isNotEmpty && instructor == instructor.toUpperCase()) {
            return instructor;
          }
        }
      }
    }
    
    // If no all-caps instructor found, return the first instructor
    for (var section in course.sections) {
      final instructorField = section.instructor.trim();
      if (instructorField.isNotEmpty) {
        // Return the first instructor from comma-separated list
        final firstInstructor = instructorField.split(',').first.trim();
        if (firstInstructor.isNotEmpty) {
          return firstInstructor;
        }
      }
    }
    
    return 'Unknown';
  }

  /// Matches every whitespace-separated term independently rather than the
  /// query as one contiguous substring, so "programming computer" finds
  /// "Computer Programming" and "csf111" finds "CS F111".
  ///
  /// Results lead with code matches because callers cap the list — an
  /// unranked cap can drop the exact code the user typed off the end.
  static List<Course> searchCourses(List<Course> courses, String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return courses;

    final flatQuery = terms.join();
    final hits = <({int rank, int order, Course course})>[];

    for (var i = 0; i < courses.length; i++) {
      final course = courses[i];
      final code = course.courseCode.toLowerCase();
      // The despaced code goes in the haystack too so a term can straddle the
      // space in "CS F111"; instructors are searchable alongside code + title.
      final flatCode = code.replaceAll(' ', '');
      final haystack = '$code $flatCode ${course.courseTitle.toLowerCase()} '
          '${course.sections.map((s) => s.instructor.toLowerCase()).join(' ')}';

      if (!terms.every(haystack.contains)) continue;

      hits.add((
        rank: flatCode == flatQuery
            ? 0
            : flatCode.startsWith(flatQuery)
                ? 1
                : 2,
        order: i,
        course: course,
      ));
    }

    // List.sort isn't stable, so `order` carries the caller's ordering
    // (alphabetical by code) through as the tie-break within a rank.
    hits.sort((a, b) =>
        a.rank != b.rank ? a.rank.compareTo(b.rank) : a.order.compareTo(b.order));
    return [for (final h in hits) h.course];
  }

  static List<Course> filterByInstructor(List<Course> courses, String instructorName) {
    if (instructorName.isEmpty) return courses;
    
    final lowercaseInstructor = instructorName.toLowerCase();
    
    return courses.where((course) {
      return course.sections.any((section) =>
          section.instructor.toLowerCase().contains(lowercaseInstructor));
    }).toList();
  }

  static List<Course> filterByCourseCode(List<Course> courses, String courseCode) {
    if (courseCode.isEmpty) return courses;
    
    final lowercaseCourseCode = courseCode.toLowerCase();
    
    return courses.where((course) {
      return course.courseCode.toLowerCase().contains(lowercaseCourseCode);
    }).toList();
  }

  static List<Course> filterByExamDate(List<Course> courses, DateTime? examDate, bool isMidSem) {
    if (examDate == null) return courses;
    
    return courses.where((course) {
      final exam = isMidSem ? course.midSemExam : course.endSemExam;
      if (exam == null) return false;
      
      return exam.date.day == examDate.day &&
             exam.date.month == examDate.month &&
             exam.date.year == examDate.year;
    }).toList();
  }

  static List<Course> filterByCredits(List<Course> courses, int? minCredits, int? maxCredits) {
    return courses.where((course) {
      // The course's own number, not its unit count: a credit-hours course has
      // no units, so comparing totalCredits hid every one of them behind any
      // "at least 1 credit" filter.
      final amount = course.variants.first.amount;
      if (minCredits != null && amount < minCredits) return false;
      if (maxCredits != null && amount > maxCredits) return false;
      return true;
    }).toList();
  }

  static List<Course> filterByDays(List<Course> courses, List<DayOfWeek> selectedDays) {
    if (selectedDays.isEmpty) return courses;

    return courses.where((course) {
      return course.sections.any((section) =>
          section.schedule.any((scheduleEntry) =>
              scheduleEntry.days.any((day) => selectedDays.contains(day))));
    }).toList();
  }

  static List<Course> filterByHours(List<Course> courses, List<int> selectedHours) {
    if (selectedHours.isEmpty) return courses;

    return courses.where((course) {
      return course.sections.any((section) =>
          section.schedule.any((scheduleEntry) =>
              scheduleEntry.hours.any((hour) => selectedHours.contains(hour))));
    }).toList();
  }

  /// Drops courses that offer no sections at all.
  ///
  /// Such a course cannot be added to a timetable, so it is noise in a list
  /// whose whole purpose is picking a section. They exist because the booklet
  /// prints each course in both semester tables and the copy for the term it
  /// is not offered in carries no rows.
  static List<Course> filterOutSectionless(List<Course> courses) =>
      courses.where((c) => c.sections.isNotEmpty).toList();
}
