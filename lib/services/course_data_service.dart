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

  /// Fetch all courses from Firestore
  Future<List<Course>> fetchCourses() async {
    try {
      final currentCampus = CampusService.currentCampus;
      
      // Check if cache is valid by comparing version with database
      final cacheValid = await _isCacheValid(currentCampus);
      
      print('🔍 Cache validation result: $cacheValid');
      print('🔍 Cached courses count: ${_cachedCourses?.length ?? 0}');
      print('🔍 Cached campus: $_cachedCampus');
      print('🔍 Current campus: $currentCampus');
      print('🔍 Cached version: $_cachedVersion');
      
      if (cacheValid && _cachedCourses != null) {
        print('✅ Using cached courses for ${CampusService.getCampusDisplayName(currentCampus)} (${_cachedCourses!.length} courses)');
        return _cachedCourses!;
      }
      
      print('❌ Cache invalid, fetching fresh data from Firestore...');

      print('🔥 FIRESTORE READ: Fetching courses from Firestore...');
      print('Collection: ${_config.coursesCollection}');
      
      final QuerySnapshot snapshot = await _firestore
          .collection(_config.coursesCollection)
          .get();

      print('Firestore query completed. Docs count: ${snapshot.docs.length}');

      if (snapshot.docs.isEmpty) {
        print('No courses found in Firestore');
        return [];
      }

      final courses = <Course>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        try {
          final doc = snapshot.docs[i];
          final data = doc.data() as Map<String, dynamic>;
          // print('Processing course ${i + 1}/${snapshot.docs.length}: ${doc.id}');
          final course = Course.fromJson(data);
          courses.add(course);
        } catch (e) {
          print('Error parsing course at index $i: $e');
          print('Document ID: ${snapshot.docs[i].id}');
          // Continue with other courses instead of failing completely
        }
      }

      print('Successfully parsed ${courses.length} courses from Firestore');
      
      // Get the current version to cache alongside the courses
      final metadata = await _getCurrentMetadata(currentCampus);
      final currentVersion = metadata?['version'] as String?;
      
      // Update cache with current campus and version
      _cachedCourses = courses;
      _lastFetchTime = DateTime.now();
      _cachedCampus = currentCampus;
      _cachedVersion = currentVersion;
      
      return courses;
    } catch (e) {
      print('Error fetching courses from Firestore: $e');
      print('Error type: ${e.runtimeType}');
      
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