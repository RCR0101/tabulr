import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/all_course.dart';
import '../models/course.dart';
import 'campus_service.dart';
import 'secure_logger.dart';

class CourseCatalogService {
  static final CourseCatalogService _instance = CourseCatalogService._internal();
  factory CourseCatalogService() => _instance;
  CourseCatalogService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, String> _courseTitleCache = {};
  DateTime? _titleCacheExpiry;

  List<AllCourse>? _cachedCourses;
  DateTime? _lastFetchTime;
  static const Duration _cacheExpiration = Duration(hours: 24);

  bool get _isTitleCacheExpired {
    return _titleCacheExpiry == null || DateTime.now().isAfter(_titleCacheExpiry!);
  }

  Future<List<AllCourse>> fetchAllCourses({bool forceRefresh = false, Campus? campus}) async {
    try {
      if (!forceRefresh &&
          _cachedCourses != null &&
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < _cacheExpiration) {
        return _cachedCourses!;
      }

      String collectionName = 'all_courses';
      if (campus != null) {
        final campusCode = CampusService.getCampusCode(campus);
        collectionName = 'all_courses_$campusCode';
      }

      final snapshot = await _firestore.collection(collectionName).get();

      final courses = snapshot.docs
          .map((doc) => AllCourse.fromFirestore(doc.data()))
          .toList();

      courses.sort((a, b) => a.courseCode.compareTo(b.courseCode));

      _cachedCourses = courses;
      _lastFetchTime = DateTime.now();

      return courses;
    } catch (e) {
      if (_cachedCourses != null) {
        return _cachedCourses!;
      }
      return [];
    }
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
    if (courseCode.isEmpty) return courseCode;

    final cacheKey = '${campus?.toString() ?? 'default'}_$courseCode';
    if (_courseTitleCache.containsKey(cacheKey) && !_isTitleCacheExpired) {
      return _courseTitleCache[cacheKey]!;
    }

    try {
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

        _courseTitleCache[cacheKey] = course.courseTitle;
        _titleCacheExpiry = DateTime.now().add(const Duration(hours: 1));

        return course.courseTitle;
      }

      _courseTitleCache[cacheKey] = courseCode;
      _titleCacheExpiry = DateTime.now().add(const Duration(hours: 1));

      return courseCode;
    } catch (e) {
      SecureLogger.error('COURSE_CATALOG', 'Error fetching course title for $courseCode', e);
      return courseCode;
    }
  }

  Future<Map<String, String>> getCourseTitles(List<String> courseCodes, {Campus? campus}) async {
    if (courseCodes.isEmpty) return {};

    final results = <String, String>{};
    final uncachedCodes = <String>[];

    final campusPrefix = '${campus?.toString() ?? 'default'}_';

    for (final courseCode in courseCodes) {
      if (courseCode.isEmpty) continue;

      final cacheKey = '$campusPrefix$courseCode';
      if (_courseTitleCache.containsKey(cacheKey) && !_isTitleCacheExpired) {
        results[courseCode] = _courseTitleCache[cacheKey]!;
      } else {
        uncachedCodes.add(courseCode);
      }
    }

    if (uncachedCodes.isNotEmpty) {
      try {
        String collectionName = 'all_courses';
        if (campus != null) {
          final campusCode = CampusService.getCampusCode(campus);
          collectionName = 'all_courses_$campusCode';
        }

        final querySnapshot = await _firestore
            .collection(collectionName)
            .where('course_code', whereIn: uncachedCodes.take(10).toList())
            .get();

        for (final doc in querySnapshot.docs) {
          final course = AllCourse.fromFirestore(doc.data());
          final cacheKey = '$campusPrefix${course.courseCode}';

          results[course.courseCode] = course.courseTitle;
          _courseTitleCache[cacheKey] = course.courseTitle;
        }

        for (final courseCode in uncachedCodes) {
          if (!results.containsKey(courseCode)) {
            results[courseCode] = courseCode;
            final cacheKey = '$campusPrefix$courseCode';
            _courseTitleCache[cacheKey] = courseCode;
          }
        }

        _titleCacheExpiry = DateTime.now().add(const Duration(hours: 1));
      } catch (e) {
        SecureLogger.error('COURSE_CATALOG', 'Error fetching course titles', e);
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
    if (_courseTitleCache.containsKey(cacheKey) && !_isTitleCacheExpired) {
      return _courseTitleCache[cacheKey];
    }

    return null;
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
      return await getCourseTitle(courseCode, campus: campus);
    }
  }

  void clearCache() {
    _courseTitleCache.clear();
    _titleCacheExpiry = null;
    _cachedCourses = null;
    _lastFetchTime = null;
  }
}
