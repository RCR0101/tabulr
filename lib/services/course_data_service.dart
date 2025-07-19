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
  static const Duration _cacheTimeout = Duration(hours: 24);

  /// Fetch all courses from Firestore
  Future<List<Course>> fetchCourses() async {
    try {
      final currentCampus = CampusService.currentCampus;
      
      // Check cache first - must match current campus and be within timeout
      if (_cachedCourses != null && 
          _lastFetchTime != null && 
          _cachedCampus == currentCampus &&
          DateTime.now().difference(_lastFetchTime!) < _cacheTimeout) {
        print('Using cached courses for ${CampusService.getCampusDisplayName(currentCampus)} (${_cachedCourses!.length} courses)');
        return _cachedCourses!;
      }

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
          print('Processing course ${i + 1}/${snapshot.docs.length}: ${doc.id}');
          final course = Course.fromJson(data);
          courses.add(course);
        } catch (e) {
          print('Error parsing course at index $i: $e');
          print('Document ID: ${snapshot.docs[i].id}');
          // Continue with other courses instead of failing completely
        }
      }

      print('Successfully parsed ${courses.length} courses from Firestore');
      
      // Update cache with current campus
      _cachedCourses = courses;
      _lastFetchTime = DateTime.now();
      _cachedCampus = currentCampus;
      
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

  /// Get metadata about the timetable data
  Future<Map<String, dynamic>?> getMetadata() async {
    try {
      final DocumentSnapshot doc = await _firestore
          .collection(_config.timetableMetadataCollection)
          .doc('current')
          .get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
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

  /// Clear the cache (useful for testing or forcing refresh)
  void clearCache() {
    _cachedCourses = null;
    _lastFetchTime = null;
    _cachedCampus = null;
  }

  /// Get cached courses if available
  List<Course>? getCachedCourses() {
    return _cachedCourses;
  }
}