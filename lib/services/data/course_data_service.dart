import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/course.dart';
import 'campus_service.dart';
import 'courses_master_service.dart';
import 'local_cache_service.dart';
import '../ui/secure_logger.dart';

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
  final LocalCacheService _localCache = LocalCacheService();

  // Campus-aware cache for courses
  List<Course>? _cachedCourses;
  DateTime? _lastFetchTime;
  Campus? _cachedCampus;
  String? _cachedVersion;
  Completer<List<Course>>? _loadCompleter;

  /// Persistent cache key. The in-memory cache above only survives one session;
  /// this one survives page reloads, which is what actually drives read cost.
  String get _cacheKey => 'courses_${CampusService.campusId}';

  /// Key used to stash the doc id inside the cached payload so [Course.fromJson]
  /// can be given the same courseCode it would get from the live doc.
  static const _codeKey = '__code';

  Course _courseFromCached(Map<String, dynamic> map) {
    final code = map[_codeKey] as String? ?? '';
    return Course.fromJson(
      map,
      courseCode: code,
      resolvedTitle: CoursesMasterService().getTitle(code),
    );
  }

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
      
      if (_loadCompleter != null) {
        return _loadCompleter!.future;
      }

      _loadCompleter = Completer<List<Course>>();

      try {
        // Persistent cache first: costs 1 metadata read instead of a full
        // collection scan. Survives page reloads, which is where the read
        // volume was coming from.
        final cachedMaps = await _localCache.readIfFresh(
          _cacheKey,
          metadataRef: CampusService.metadataDocRef(_firestore),
        );
        if (cachedMaps != null && cachedMaps.isNotEmpty) {
          final cachedCourses = cachedMaps.map(_courseFromCached).toList();
          _cachedCourses = cachedCourses;
          _lastFetchTime = DateTime.now();
          _cachedCampus = currentCampus;
          _cachedVersion =
              (await _getCurrentMetadata(currentCampus))?['version'] as String?;
          cacheHit = true;
          _loadCompleter!.complete(cachedCourses);
          _loadCompleter = null;
          return cachedCourses;
        }

        final allCourses = <Course>[];
        final rawDocs = <Map<String, dynamic>>[];
        DocumentSnapshot? lastDocument;
        bool hasMore = true;

        while (hasMore) {
          Query query = CampusService.timetableRef(_firestore)
              .limit(AppLimits.coursePageSize);
          
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
                rawDocs.add({...data, _codeKey: code});
              } catch (e) {
                // Skip unparseable course ${doc.id}
              }
            }
            
            if (snapshot.docs.length < AppLimits.coursePageSize) {
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

        // Persist so the next page load costs 1 read instead of a full scan.
        await _localCache.write(_cacheKey, rawDocs);

        _loadCompleter!.complete(allCourses);
        _loadCompleter = null;
        return allCourses;
      } catch (e) {
        _loadCompleter!.completeError(e);
        _loadCompleter = null;
        rethrow;
      }
    } catch (e) {
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.completeError(e);
        _loadCompleter = null;
      }
      
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


  /// Check if the current cache is valid by comparing versions
  Future<bool> _isCacheValid(Campus currentCampus) async {
    try {
      if (_cachedCourses == null || _lastFetchTime == null) return false;
      if (_cachedCampus != currentCampus) return false;

      final age = DateTime.now().difference(_lastFetchTime!);
      if (age > AppDurations.cacheTimeout) return false;

      // Skip Firestore version check if cache is very fresh
      if (age < AppDurations.versionCheckInterval) return true;

      final metadata = await _getCurrentMetadata(currentCampus);
      final currentVersion = metadata?['version'] as String?;

      if (currentVersion == null) return true;

      return _cachedVersion != null && _cachedVersion == currentVersion;
    } catch (e) {
      return _lastFetchTime != null &&
             DateTime.now().difference(_lastFetchTime!) < AppDurations.cacheTimeout;
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