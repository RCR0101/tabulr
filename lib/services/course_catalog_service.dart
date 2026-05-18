import '../models/all_course.dart';
import '../models/course.dart';
import 'campus_service.dart';
import 'courses_master_service.dart';

class CourseCatalogService {
  static final CourseCatalogService _instance = CourseCatalogService._internal();
  factory CourseCatalogService() => _instance;
  CourseCatalogService._internal();

  Future<List<AllCourse>> fetchAllCourses({bool forceRefresh = false, Campus? campus}) async {
    final master = CoursesMasterService();
    if (!master.isLoaded || forceRefresh) {
      await master.loadForCampus();
    }

    final courses = master.allCourses.map((e) => AllCourse(
      courseCode: e.courseCode,
      courseTitle: e.title,
      creditValue: e.credits,
      type: e.type,
    )).toList();

    courses.sort((a, b) => a.courseCode.compareTo(b.courseCode));
    return courses;
  }

  List<AllCourse> searchCourses(List<AllCourse> courses, String query) {
    if (query.isEmpty) return courses;

    final lowerQuery = query.toLowerCase();
    return courses.where((course) {
      return course.courseCode.toLowerCase().contains(lowerQuery) ||
          course.courseTitle.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  Future<String> getCourseTitle(String courseCode, {Campus? campus}) async {
    return CoursesMasterService().getTitle(courseCode);
  }

  Future<Map<String, String>> getCourseTitles(List<String> courseCodes, {Campus? campus}) async {
    final results = <String, String>{};
    for (final code in courseCodes) {
      results[code] = CoursesMasterService().getTitle(code);
    }
    return results;
  }

  String? getCachedCourseTitle(String courseCode, {Campus? campus}) {
    final master = CoursesMasterService();
    if (!master.isLoaded) return null;
    final entry = master.get(courseCode);
    return entry?.title;
  }

  Future<String> getCourseTitleWithFallback(
    String courseCode,
    List<Course> availableCourses,
    {Campus? campus}
  ) async {
    if (courseCode.isEmpty) return courseCode;

    try {
      final course = availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
      );
      return course.courseTitle;
    } catch (e) {
      return CoursesMasterService().getTitle(courseCode);
    }
  }

  void clearCache() {
    // No-op: cache lives in CoursesMasterService
  }
}
