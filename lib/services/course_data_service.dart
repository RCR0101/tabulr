import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import 'campus_service.dart';
import 'courses_master_service.dart';
import 'secure_logger.dart';

class CourseDataService {
  static final CourseDataService _instance = CourseDataService._internal();
  factory CourseDataService() => _instance;
  CourseDataService._internal() {
    // Listen for campus changes and clear cache
    CampusService.campusChangeStream.listen((_) {
      clearCache();
    });
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Campus-aware cache for courses
  List<Course>? _cachedCourses;
  DateTime? _lastFetchTime;
  Campus? _cachedCampus;
  String? _cachedVersion; // Track the version of cached data
  static const Duration _cacheTimeout = Duration(hours: 24);
  
  // Pagination constants
  static const int _pageSize = 100;
  bool _isLoadingAllCourses = false;

  /// Fetch courses with pagination support
  Future<List<Course>> fetchCoursesWithPagination({
    DocumentSnapshot? startAfter,
    int limit = 100,
  }) async {
    try {
      Query query = CampusService.timetableRef(_firestore)
          .limit(limit);
      
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      
      final QuerySnapshot snapshot = await query.get();

      final courses = <Course>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        try {
          final doc = snapshot.docs[i];
          final data = doc.data() as Map<String, dynamic>;
          final code = doc.id.replaceAll('_', ' ');
          final title = CoursesMasterService().getTitle(code);
          final course = Course.fromJson(data, courseCode: code, resolvedTitle: title);
          courses.add(course);
        } catch (e) {
          // Skip unparseable course at index $i
        }
      }

      return courses;
    } catch (e) {
      throw Exception('Failed to fetch courses: $e');
    }
  }

  /// Fetch all courses from Firestore using pagination (optimized)
  Future<List<Course>> fetchCourses() async {
    final perfSw = Stopwatch()..start();
    bool cacheHit = false;
    try {
      final currentCampus = CampusService.currentCampus;

      // Check if cache is valid by comparing version with database
      final cacheValid = await _isCacheValid(currentCampus);

      if (cacheValid && _cachedCourses != null) {
        cacheHit = true;
        return _cachedCourses!;
      }
      
      if (_isLoadingAllCourses) {
        // If already loading, wait for completion by checking cache periodically
        while (_isLoadingAllCourses) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_cachedCourses != null) return _cachedCourses!;
      }
      
      _isLoadingAllCourses = true;
      
      try {
        final allCourses = <Course>[];
        DocumentSnapshot? lastDocument;
        bool hasMore = true;
        
        while (hasMore) {
          Query query = CampusService.timetableRef(_firestore)
              .limit(_pageSize);
          
          if (lastDocument != null) {
            query = query.startAfterDocument(lastDocument);
          }
          
          final snapshot = await query.get();
          
          if (snapshot.docs.isEmpty) {
            hasMore = false;
          } else {
            for (final doc in snapshot.docs) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final code = doc.id.replaceAll('_', ' ');
                final title = CoursesMasterService().getTitle(code);
                final course = Course.fromJson(data, courseCode: code, resolvedTitle: title);
                allCourses.add(course);
              } catch (e) {
                // Skip unparseable course ${doc.id}
              }
            }
            
            if (snapshot.docs.length < _pageSize) {
              hasMore = false;
            } else {
              lastDocument = snapshot.docs.last;
            }
          }
        }

        // Get the current version to cache alongside the courses
        final metadata = await _getCurrentMetadata(currentCampus);
        final currentVersion = metadata?['version'] as String?;
        
        // Update cache with current campus and version
        _cachedCourses = allCourses;
        _lastFetchTime = DateTime.now();
        _cachedCampus = currentCampus;
        _cachedVersion = currentVersion;
        
        return allCourses;
      } finally {
        _isLoadingAllCourses = false;
      }
    } catch (e) {
      _isLoadingAllCourses = false;
      
      // If it's a network/connection error, provide a clearer message
      if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception('Permission denied. Please check Firestore security rules.');
      } else if (e.toString().contains('UNAVAILABLE')) {
        throw Exception('Firestore is currently unavailable. Please try again later.');
      } else if (e.toString().contains('JSON') || e.toString().contains('token')) {
        throw Exception('Network connection error. Please check your internet connection.');
      }
      
      throw Exception('Failed to fetch courses: $e');
    } finally {
      perfSw.stop();
      SecureLogger.performance('fetch_courses', perfSw.elapsed, {'cache_hit': cacheHit});
    }
  }

  /// Get metadata about the timetable data for current campus
  Future<Map<String, dynamic>?> getMetadata() async {
    try {
      final currentCampus = CampusService.currentCampus;
      return await _getCurrentMetadata(currentCampus);
    } catch (e) {
      return null;
    }
  }

  /// Check if courses data is available
  Future<bool> isDataAvailable() async {
    try {
      final metadata = await getMetadata();
      return metadata != null && metadata['totalCourses'] != null;
    } catch (e) {
      return false;
    }
  }

  static const Duration _versionCheckInterval = Duration(minutes: 5);

  /// Check if the current cache is valid by comparing versions
  Future<bool> _isCacheValid(Campus currentCampus) async {
    try {
      if (_cachedCourses == null || _lastFetchTime == null) return false;
      if (_cachedCampus != currentCampus) return false;

      final age = DateTime.now().difference(_lastFetchTime!);
      if (age > _cacheTimeout) return false;

      // Skip Firestore version check if cache is very fresh
      if (age < _versionCheckInterval) return true;

      final metadata = await _getCurrentMetadata(currentCampus);
      final currentVersion = metadata?['version'] as String?;

      if (currentVersion == null) return true;

      return _cachedVersion != null && _cachedVersion == currentVersion;
    } catch (e) {
      return _lastFetchTime != null &&
             DateTime.now().difference(_lastFetchTime!) < _cacheTimeout;
    }
  }
  
  /// Get metadata for the current campus
  Future<Map<String, dynamic>?> _getCurrentMetadata(Campus campus) async {
    try {
      final DocumentSnapshot doc = await CampusService.metadataDocRef(_firestore).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Clear the cache (useful for testing or forcing refresh)
  void clearCache() {
    _cachedCourses = null;
    _lastFetchTime = null;
    _cachedCampus = null;
    _cachedVersion = null;
  }

  /// Get cached courses if available
  List<Course>? getCachedCourses() {
    return _cachedCourses;
  }
}