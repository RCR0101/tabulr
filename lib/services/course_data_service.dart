import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import 'config_service.dart';
import 'campus_service.dart';

class CourseDataService {
  static final CourseDataService _instance = CourseDataService._internal();
  factory CourseDataService() => _instance;
  CourseDataService._internal() {
    // Listen for campus changes and clear cache
    CampusService.campusChangeStream.listen((_) {
      print('Campus changed, clearing course cache...');
      clearCache();
    });
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ConfigService _config = ConfigService();
  
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
      print('🔥 FIRESTORE READ: Fetching courses with pagination (limit: $limit)');
      
      Query query = _firestore
          .collection(_config.coursesCollection)
          .limit(limit);
      
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      
      final QuerySnapshot snapshot = await query.get();
      print('Firestore paginated query completed. Docs count: ${snapshot.docs.length}');

      final courses = <Course>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        try {
          final doc = snapshot.docs[i];
          final data = doc.data() as Map<String, dynamic>;
          final course = Course.fromJson(data);
          courses.add(course);
        } catch (e) {
          print('Error parsing course at index $i: $e');
        }
      }

      return courses;
    } catch (e) {
      print('Error fetching courses with pagination: $e');
      throw Exception('Failed to fetch courses: $e');
    }
  }

  /// Fetch all courses from Firestore using pagination (optimized)
  Future<List<Course>> fetchCourses() async {
    try {
      final currentCampus = CampusService.currentCampus;
      
      // Check if cache is valid by comparing version with database
      final cacheValid = await _isCacheValid(currentCampus);
      
      if (cacheValid && _cachedCourses != null) {
        print('✅ Using cached courses for ${CampusService.getCampusDisplayName(currentCampus)} (${_cachedCourses!.length} courses)');
        return _cachedCourses!;
      }
      
      print('❌ Cache invalid, fetching fresh data with pagination...');
      
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
          Query query = _firestore
              .collection(_config.coursesCollection)
              .limit(_pageSize);
          
          if (lastDocument != null) {
            query = query.startAfterDocument(lastDocument);
          }
          
          final snapshot = await query.get();
          
          if (snapshot.docs.isEmpty) {
            hasMore = false;
          } else {
            // Parse courses from this batch
            for (final doc in snapshot.docs) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final course = Course.fromJson(data);
                allCourses.add(course);
              } catch (e) {
                print('Error parsing course ${doc.id}: $e');
              }
            }
            
            if (snapshot.docs.length < _pageSize) {
              hasMore = false;
            } else {
              lastDocument = snapshot.docs.last;
            }
          }
        }

        print('Successfully fetched ${allCourses.length} courses using pagination');
        
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
      print('Error fetching courses from Firestore: $e');
      
      // If it's a network/connection error, provide a clearer message
      if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception('Permission denied. Please check Firestore security rules.');
      } else if (e.toString().contains('UNAVAILABLE')) {
        throw Exception('Firestore is currently unavailable. Please try again later.');
      } else if (e.toString().contains('JSON') || e.toString().contains('token')) {
        throw Exception('Network connection error. Please check your internet connection.');
      }
      
      throw Exception('Failed to fetch courses: $e');
    }
  }

  /// Get metadata about the timetable data for current campus
  Future<Map<String, dynamic>?> getMetadata() async {
    try {
      final currentCampus = CampusService.currentCampus;
      return await _getCurrentMetadata(currentCampus);
    } catch (e) {
      print('Error fetching metadata: $e');
      return null;
    }
  }

  /// Check if courses data is available
  Future<bool> isDataAvailable() async {
    try {
      final metadata = await getMetadata();
      return metadata != null && metadata['totalCourses'] != null;
    } catch (e) {
      print('Error checking data availability: $e');
      return false;
    }
  }

  /// Check if the current cache is valid by comparing versions
  Future<bool> _isCacheValid(Campus currentCampus) async {
    try {
      print('🔍 _isCacheValid: Starting validation...');
      print('🔍 _cachedCourses: ${_cachedCourses != null ? "exists (${_cachedCourses!.length})" : "null"}');
      print('🔍 _cachedCampus: $_cachedCampus vs currentCampus: $currentCampus');
      print('🔍 _lastFetchTime: $_lastFetchTime');
      
      // Basic checks: cache exists, campus matches, and not too old (fallback)
      if (_cachedCourses == null) {
        print('🔍 Cache invalid: no cached courses');
        return false;
      }
      
      if (_cachedCampus != currentCampus) {
        print('🔍 Cache invalid: campus mismatch');
        return false;
      }
      
      if (_lastFetchTime == null) {
        print('🔍 Cache invalid: no fetch time');
        return false;
      }
      
      if (DateTime.now().difference(_lastFetchTime!) > _cacheTimeout) {
        print('🔍 Cache invalid: timeout exceeded');
        return false;
      }
      
      print('🔍 Basic cache checks passed, checking version...');
      
      // Version check: compare cached version with current database version
      final metadata = await _getCurrentMetadata(currentCampus);
      print('🔍 Retrieved metadata: $metadata');
      
      final currentVersion = metadata?['version'] as String?;
      print('🔍 Current DB version: $currentVersion');
      print('🔍 Cached version: $_cachedVersion');
      
      // If we can't get the current version, fall back to time-based cache
      if (currentVersion == null) {
        print('🔍 No current version found, using time-based cache');
        return DateTime.now().difference(_lastFetchTime!) < _cacheTimeout;
      }
      
      // Cache is valid if versions match
      final versionsMatch = _cachedVersion != null && _cachedVersion == currentVersion;
      
      if (!versionsMatch) {
        print('📦 Cache invalidated: version mismatch (cached: $_cachedVersion, current: $currentVersion)');
      } else {
        print('✅ Cache valid: versions match');
      }
      
      return versionsMatch;
    } catch (e) {
      print('Error checking cache validity: $e');
      // On error, fall back to time-based cache validation
      return _lastFetchTime != null && 
             DateTime.now().difference(_lastFetchTime!) < _cacheTimeout;
    }
  }
  
  /// Get metadata for the current campus
  Future<Map<String, dynamic>?> _getCurrentMetadata(Campus campus) async {
    try {
      String docName;
      switch (campus) {
        case Campus.hyderabad:
          docName = 'current-hyderabad';
          break;
        case Campus.pilani:
          docName = 'current-pilani';
          break;
        case Campus.goa:
          docName = 'current-goa';
          break;
      }
      
      final DocumentSnapshot doc = await _firestore
          .collection(_config.timetableMetadataCollection)
          .doc(docName)
          .get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error fetching current metadata: $e');
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