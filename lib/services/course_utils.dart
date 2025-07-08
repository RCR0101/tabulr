import '../models/course.dart';

class CourseUtils {
  static String getInstructorInCharge(Course course) {
    for (var section in course.sections) {
      final instructor = section.instructor.trim();
      if (instructor.isNotEmpty && instructor == instructor.toUpperCase()) {
        return instructor;
      }
    }
    
    // If no all-caps instructor found, return the first instructor
    for (var section in course.sections) {
      if (section.instructor.trim().isNotEmpty) {
        return section.instructor.trim();
      }
    }
    
    return 'Unknown';
  }

  static List<Course> searchCourses(List<Course> courses, String query) {
    if (query.isEmpty) return courses;
    
    final lowercaseQuery = query.toLowerCase();
    
    return courses.where((course) {
      // Search in course code
      if (course.courseCode.toLowerCase().contains(lowercaseQuery)) {
        return true;
      }
      
      // Search in course title
      if (course.courseTitle.toLowerCase().contains(lowercaseQuery)) {
        return true;
      }
      
      // Search in instructor names
      for (var section in course.sections) {
        if (section.instructor.toLowerCase().contains(lowercaseQuery)) {
          return true;
        }
      }
      
      return false;
    }).toList();
  }

  static List<Course> filterByInstructor(List<Course> courses, String instructorName) {
    if (instructorName.isEmpty) return courses;
    
    final lowercaseInstructor = instructorName.toLowerCase();
    
    return courses.where((course) {
      return course.sections.any((section) =>
          section.instructor.toLowerCase().contains(lowercaseInstructor));
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
      if (minCredits != null && course.totalCredits < minCredits) return false;
      if (maxCredits != null && course.totalCredits > maxCredits) return false;
      return true;
    }).toList();
  }

  static List<Course> filterByDays(List<Course> courses, List<DayOfWeek> selectedDays) {
    if (selectedDays.isEmpty) return courses;
    
    return courses.where((course) {
      return course.sections.any((section) =>
          section.days.any((day) => selectedDays.contains(day)));
    }).toList();
  }
}