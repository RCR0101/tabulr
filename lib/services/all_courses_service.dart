import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/all_course.dart';

class AllCoursesService {
  static final AllCoursesService _instance = AllCoursesService._internal();
  factory AllCoursesService() => _instance;
  AllCoursesService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<AllCourse>? _cachedCourses;
  DateTime? _lastFetchTime;
  static const Duration _cacheExpiration = Duration(hours: 24);

  // Fetch all courses from Firestore
  Future<List<AllCourse>> fetchAllCourses({bool forceRefresh = false}) async {
    try {
      // Return cached data if it's still valid and not forcing refresh
      if (!forceRefresh &&
          _cachedCourses != null &&
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < _cacheExpiration) {
        print('Returning cached courses (${_cachedCourses!.length} courses)');
        return _cachedCourses!;
      }

      print('Fetching all courses from Firestore...');
      final snapshot = await _firestore.collection('all_courses').get();

      final courses =
          snapshot.docs
              .map((doc) => AllCourse.fromFirestore(doc.data()))
              .toList();

      // Sort courses by course code
      courses.sort((a, b) => a.courseCode.compareTo(b.courseCode));

      // Cache the results
      _cachedCourses = courses;
      _lastFetchTime = DateTime.now();

      print('Fetched ${courses.length} courses from Firestore');
      return courses;
    } catch (e) {
      print('Error fetching all courses: $e');
      // Return cached data if available, even if expired
      if (_cachedCourses != null) {
        print('Returning cached courses due to error');
        return _cachedCourses!;
      }
      return [];
    }
  }

  // Search courses by code or title
  List<AllCourse> searchCourses(List<AllCourse> courses, String query) {
    if (query.isEmpty) return courses;

    final lowerQuery = query.toLowerCase();
    return courses.where((course) {
      return course.courseCode.toLowerCase().contains(lowerQuery) ||
          course.courseTitle.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  // Clear cache (useful for testing or when data needs to be refreshed)
  void clearCache() {
    _cachedCourses = null;
    _lastFetchTime = null;
    print('All courses cache cleared');
  }
}
