import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../models/course.dart';
import '../services/config_service.dart';
import '../services/campus_service.dart';
import 'campus_provider.dart';

part 'course_data_provider.freezed.dart';

/// State class for course data management
@freezed
class CourseDataState with _$CourseDataState {
  const factory CourseDataState({
    @Default([]) List<Course> courses,
    @Default(false) bool isLoading,
    @Default(false) bool isLoadingMore,
    @Default(false) bool hasMore,
    DocumentSnapshot? lastDocument,
    DateTime? lastFetchTime,
    Campus? cachedCampus,
    String? cachedVersion,
    String? error,
    Map<String, dynamic>? metadata,
  }) = _CourseDataState;
}

/// Course data service provider for dependency injection
final courseDataServiceProvider = Provider<CourseDataNotifier>((ref) {
  return CourseDataNotifier();
});

/// Main course data provider
final courseDataProvider = StateNotifierProvider<CourseDataNotifier, CourseDataState>((ref) {
  final notifier = ref.watch(courseDataServiceProvider);
  
  // Listen to campus changes and clear cache when campus changes
  ref.listen(currentCampusProvider, (previous, next) {
    if (previous != next) {
      notifier.clearCache();
    }
  });
  
  return notifier;
});

/// Derived providers for specific data access
final coursesProvider = Provider<List<Course>>((ref) {
  return ref.watch(courseDataProvider).courses;
});

final isLoadingCoursesProvider = Provider<bool>((ref) {
  return ref.watch(courseDataProvider).isLoading;
});

final courseMetadataProvider = Provider<Map<String, dynamic>?>((ref) {
  return ref.watch(courseDataProvider).metadata;
});

final isDataAvailableProvider = Provider<bool>((ref) {
  final metadata = ref.watch(courseMetadataProvider);
  return metadata != null && metadata['totalCourses'] != null;
});

/// Provider to get a specific course by course code
final courseByCodeProvider = Provider.family<Course?, String>((ref, courseCode) {
  final courses = ref.watch(coursesProvider);
  try {
    return courses.firstWhere((course) => course.courseCode == courseCode);
  } catch (e) {
    return null;
  }
});

/// Provider to search courses by various criteria
final searchCoursesProvider = Provider.family<List<Course>, String>((ref, searchTerm) {
  final courses = ref.watch(coursesProvider);
  if (searchTerm.isEmpty) return courses;
  
  final term = searchTerm.toLowerCase();
  return courses.where((course) {
    return course.courseCode.toLowerCase().contains(term) ||
           course.courseTitle.toLowerCase().contains(term) ||
           course.sections.any((section) => section.instructor.toLowerCase().contains(term));
  }).toList();
});

/// Course data state notifier that manages all course data operations
class CourseDataNotifier extends StateNotifier<CourseDataState> {
  static const Duration _cacheTimeout = Duration(hours: 24);
  static const int _pageSize = 100;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ConfigService _config = ConfigService();
  
  bool _isLoadingAllCourses = false;

  CourseDataNotifier() : super(const CourseDataState());

  /// Fetch all courses from Firestore using pagination (optimized)
  Future<void> fetchCourses() async {
    final currentCampus = CampusService.currentCampus;
    
    // Check if cache is valid by comparing version with database
    final cacheValid = await _isCacheValid(currentCampus);
    
    if (cacheValid && state.courses.isNotEmpty) {
      return;
    }
    
    if (_isLoadingAllCourses) {
      // If already loading, wait for completion by checking state periodically
      while (_isLoadingAllCourses && state.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    
    _isLoadingAllCourses = true;
    state = state.copyWith(isLoading: true, error: null);
    
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
              // Skip invalid course data
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
      
      // Update state with fetched data
      state = state.copyWith(
        courses: allCourses,
        lastFetchTime: DateTime.now(),
        cachedCampus: currentCampus,
        cachedVersion: currentVersion,
        metadata: metadata,
        isLoading: false,
        hasMore: false,
        lastDocument: null,
        error: null,
      );
      
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
    } finally {
      _isLoadingAllCourses = false;
    }
  }

  /// Fetch courses with pagination for incremental loading
  Future<void> fetchCoursesWithPagination({
    bool loadMore = false,
    int limit = 100,
  }) async {
    if (state.isLoading || state.isLoadingMore || (!loadMore && !state.hasMore)) {
      return;
    }
    
    if (loadMore) {
      state = state.copyWith(isLoadingMore: true, error: null);
    } else {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      Query query = _firestore
          .collection(_config.coursesCollection)
          .limit(limit);
      
      if (loadMore && state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }
      
      final QuerySnapshot snapshot = await query.get();

      final newCourses = <Course>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final course = Course.fromJson(data);
          newCourses.add(course);
        } catch (e) {
          // Skip invalid course data
        }
      }

      final allCourses = loadMore 
          ? [...state.courses, ...newCourses]
          : newCourses;
          
      final hasMore = snapshot.docs.length == limit;
      final lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

      state = state.copyWith(
        courses: allCourses,
        lastDocument: lastDocument,
        hasMore: hasMore,
        isLoading: false,
        isLoadingMore: false,
        error: null,
      );

    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: _getErrorMessage(e),
      );
    }
  }

  /// Load more courses (for pagination)
  Future<void> loadMoreCourses() async {
    await fetchCoursesWithPagination(loadMore: true);
  }

  /// Get metadata about the timetable data for current campus
  Future<void> fetchMetadata() async {
    try {
      final currentCampus = CampusService.currentCampus;
      final metadata = await _getCurrentMetadata(currentCampus);
      state = state.copyWith(metadata: metadata);
    } catch (e) {
      state = state.copyWith(error: 'Failed to fetch metadata: ${e.toString()}');
    }
  }

  /// Refresh courses (clear cache and fetch new)
  Future<void> refreshCourses() async {
    clearCache();
    await fetchCourses();
  }

  /// Clear the cache and reset state
  void clearCache() {
    state = const CourseDataState();
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Private helper methods

  /// Check if the current cache is valid by comparing versions
  Future<bool> _isCacheValid(Campus currentCampus) async {
    try {
      // Basic checks: cache exists, campus matches, and not too old (fallback)
      if (state.courses.isEmpty) {
        return false;
      }
      
      if (state.cachedCampus != currentCampus) {
        return false;
      }
      
      if (state.lastFetchTime == null) {
        return false;
      }
      
      if (DateTime.now().difference(state.lastFetchTime!) > _cacheTimeout) {
        return false;
      }
      
      // Version check: compare cached version with current database version
      final metadata = await _getCurrentMetadata(currentCampus);
      final currentVersion = metadata?['version'] as String?;
      
      // If we can't get the current version, fall back to time-based cache
      if (currentVersion == null) {
        return DateTime.now().difference(state.lastFetchTime!) < _cacheTimeout;
      }
      
      // Cache is valid if versions match
      return state.cachedVersion != null && state.cachedVersion == currentVersion;
    } catch (e) {
      // On error, fall back to time-based cache validation
      return state.lastFetchTime != null && 
             DateTime.now().difference(state.lastFetchTime!) < _cacheTimeout;
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
      return null;
    }
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic error) {
    final errorString = error.toString();
    
    if (errorString.contains('PERMISSION_DENIED')) {
      return 'Permission denied. Please check Firestore security rules.';
    } else if (errorString.contains('UNAVAILABLE')) {
      return 'Firestore is currently unavailable. Please try again later.';
    } else if (errorString.contains('JSON') || errorString.contains('token')) {
      return 'Network connection error. Please check your internet connection.';
    }
    
    return 'Failed to fetch courses: $errorString';
  }
}