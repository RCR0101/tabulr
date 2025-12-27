import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/all_course.dart';
import 'secure_logger.dart';

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
        SecureLogger.debug('CACHE', 'Using cached courses', {'count': _cachedCourses!.length});
        return _cachedCourses!;
      }

      SecureLogger.dataOperation('FETCH', 'all_courses', true, {'source': 'firestore'});
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

      SecureLogger.dataOperation('FETCH', 'all_courses', true, {
        'count': courses.length,
        'cached': true
      });
      return courses;
    } catch (e) {
      SecureLogger.error('DATA', 'Failed to fetch all courses', e, null, {
        'fallback_available': _cachedCourses != null
      });
      // Return cached data if available, even if expired
      if (_cachedCourses != null) {
        SecureLogger.warning('DATA', 'Using expired cache due to fetch error');
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
    SecureLogger.debug('CACHE', 'All courses cache cleared');
  }
}
