import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/all_course.dart';
import '../models/course.dart';
import 'campus_service.dart';

class AllCourseService {
  static final AllCourseService _instance = AllCourseService._internal();
  factory AllCourseService() => _instance;
  AllCourseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache for course titles to avoid repeated Firestore queries
  final Map<String, String> _courseTitleCache = {};
  
  // Cache expiry time (1 hour)
  DateTime? _cacheExpiry;
  
  bool get _isCacheExpired {
    return _cacheExpiry == null || DateTime.now().isAfter(_cacheExpiry!);
  }

  /// Get course title by course code with caching
  /// Returns the course title or the course code if not found
  Future<String> getCourseTitle(String courseCode, {Campus? campus}) async {
    if (courseCode.isEmpty) return courseCode;
    
    // Check cache first
    final cacheKey = '${campus?.toString() ?? 'default'}_$courseCode';
    if (_courseTitleCache.containsKey(cacheKey) && !_isCacheExpired) {
      return _courseTitleCache[cacheKey]!;
    }
    
    try {
      // Determine collection name based on campus
      String collectionName = 'all_courses';
      if (campus != null) {
        final campusCode = CampusService.getCampusCode(campus);
        collectionName = 'all_courses_$campusCode';
      }
      
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('course_code', isEqualTo: courseCode)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isNotEmpty) {
        final courseData = querySnapshot.docs.first.data();
        final course = AllCourse.fromFirestore(courseData);
        
        // Cache the result
        _courseTitleCache[cacheKey] = course.courseTitle;
        _cacheExpiry = DateTime.now().add(const Duration(hours: 1));
        
        return course.courseTitle;
      }
      
      // If not found, cache the courseCode itself to avoid repeated queries
      _courseTitleCache[cacheKey] = courseCode;
      _cacheExpiry = DateTime.now().add(const Duration(hours: 1));
      
      return courseCode;
    } catch (e) {
      print('Error fetching course title for $courseCode: $e');
      // Return course code if there's an error
      return courseCode;
    }
  }
  
  /// Get multiple course titles efficiently
  Future<Map<String, String>> getCourseTitles(List<String> courseCodes, {Campus? campus}) async {
    if (courseCodes.isEmpty) return {};
    
    final results = <String, String>{};
    final uncachedCodes = <String>[];
    
    final campusPrefix = '${campus?.toString() ?? 'default'}_';
    
    // Check cache for each course code
    for (final courseCode in courseCodes) {
      if (courseCode.isEmpty) continue;
      
      final cacheKey = '$campusPrefix$courseCode';
      if (_courseTitleCache.containsKey(cacheKey) && !_isCacheExpired) {
        results[courseCode] = _courseTitleCache[cacheKey]!;
      } else {
        uncachedCodes.add(courseCode);
      }
    }
    
    // Fetch uncached course titles
    if (uncachedCodes.isNotEmpty) {
      try {
        String collectionName = 'all_courses';
        if (campus != null) {
          final campusCode = CampusService.getCampusCode(campus);
          collectionName = 'all_courses_$campusCode';
        }
        
        final querySnapshot = await _firestore
            .collection(collectionName)
            .where('course_code', whereIn: uncachedCodes.take(10).toList()) // Firestore limit
            .get();
        
        // Process results
        for (final doc in querySnapshot.docs) {
          final course = AllCourse.fromFirestore(doc.data());
          final cacheKey = '$campusPrefix${course.courseCode}';
          
          results[course.courseCode] = course.courseTitle;
          _courseTitleCache[cacheKey] = course.courseTitle;
        }
        
        // Handle remaining codes that weren't found
        for (final courseCode in uncachedCodes) {
          if (!results.containsKey(courseCode)) {
            results[courseCode] = courseCode; // Use course code as fallback
            final cacheKey = '$campusPrefix$courseCode';
            _courseTitleCache[cacheKey] = courseCode;
          }
        }
        
        _cacheExpiry = DateTime.now().add(const Duration(hours: 1));
      } catch (e) {
        print('Error fetching course titles: $e');
        // For any remaining uncached codes, use the course code itself
        for (final courseCode in uncachedCodes) {
          if (!results.containsKey(courseCode)) {
            results[courseCode] = courseCode;
          }
        }
      }
    }
    
    return results;
  }
  
  String? getCachedCourseTitle(String courseCode, {Campus? campus}) {
    if (courseCode.isEmpty) return null;
    
    final cacheKey = '${campus?.toString() ?? 'default'}_$courseCode';
    if (_courseTitleCache.containsKey(cacheKey) && !_isCacheExpired) {
      return _courseTitleCache[cacheKey];
    }
    
    return null;
  }
  
  /// Clear the cache (useful for testing or when switching campuses)
  void clearCache() {
    _courseTitleCache.clear();
    _cacheExpiry = null;
  }
  
  /// Get course title with local fallback first, then remote fallback
  Future<String> getCourseTitleWithFallback(
    String courseCode, 
    List<Course> availableCourses, 
    {Campus? campus}
  ) async {
    if (courseCode.isEmpty) return courseCode;
    
    // First try to find in available courses (current semester)
    try {
      final course = availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
      );
      return course.courseTitle;
    } catch (e) {
      // Course not found in current semester, try all_courses collection
      return await getCourseTitle(courseCode, campus: campus);
    }
  }
}