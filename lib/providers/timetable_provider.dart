import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/course_data_service.dart';
import '../services/campus_service.dart';
import '../services/clash_detector.dart';
import '../services/secure_logger.dart';
import 'dart:convert';
import 'dart:js' as js;
import 'package:shared_preferences/shared_preferences.dart';

part 'timetable_provider.freezed.dart';

/// State class for timetable management
@freezed
class TimetableState with _$TimetableState {
  const factory TimetableState({
    @Default([]) List<Timetable> timetables,
    Timetable? currentTimetable,
    @Default(false) bool isLoading,
    @Default(false) bool isSaving,
    @Default(false) bool hasUnsavedChanges,
    String? error,
  }) = _TimetableState;
}

/// Timetable service provider for dependency injection
final timetableServiceProvider = Provider<TimetableNotifier>((ref) {
  return TimetableNotifier(
    authService: AuthService(),
    firestoreService: FirestoreService(),
    courseDataService: CourseDataService(),
  );
});

/// Main timetable provider
final timetableProvider = StateNotifierProvider<TimetableNotifier, TimetableState>((ref) {
  return ref.watch(timetableServiceProvider);
});

/// Convenience providers for common state access
final currentTimetableProvider = Provider<Timetable?>((ref) {
  return ref.watch(timetableProvider).currentTimetable;
});

final hasUnsavedChangesProvider = Provider<bool>((ref) {
  return ref.watch(timetableProvider).hasUnsavedChanges;
});

final isLoadingProvider = Provider<bool>((ref) {
  return ref.watch(timetableProvider).isLoading;
});

final isSavingProvider = Provider<bool>((ref) {
  return ref.watch(timetableProvider).isSaving;
});

/// Derived provider for timetable slots
final timetableSlotsProvider = Provider<List<TimetableSlot>>((ref) {
  final currentTimetable = ref.watch(currentTimetableProvider);
  if (currentTimetable == null) return [];
  
  return TimetableSlotGenerator.generateSlots(
    currentTimetable.selectedSections,
    currentTimetable.availableCourses,
  );
});

/// Derived provider for incomplete selection warnings
final incompleteWarningsProvider = Provider<List<String>>((ref) {
  final currentTimetable = ref.watch(currentTimetableProvider);
  if (currentTimetable == null) return [];
  
  return TimetableValidator.getIncompleteSelectionWarnings(
    currentTimetable.selectedSections,
    currentTimetable.availableCourses,
  );
});

/// Timetable state notifier that manages all timetable operations
class TimetableNotifier extends StateNotifier<TimetableState> {
  static const String _storageKey = 'user_timetable_data';
  static const String _timetablesListKey = 'user_timetables_list';
  
  final AuthService _authService;
  final FirestoreService _firestoreService;
  final CourseDataService _courseDataService;

  TimetableNotifier({
    required AuthService authService,
    required FirestoreService firestoreService,
    required CourseDataService courseDataService,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        _courseDataService = courseDataService,
        super(const TimetableState());

  /// Load timetable from storage (Firestore for auth users, local for guests)
  Future<void> loadTimetable() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      Timetable? timetable;

      // Load from Firestore for authenticated users
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Loading timetable from Firestore', {'storage_type': 'firestore'});
        timetable = await _firestoreService.loadTimetable();
        
        if (timetable != null) {
          SecureLogger.dataOperation('load', 'timetable_firestore', true, {'storage_type': 'firestore'});
        } else {
          SecureLogger.info('DATA', 'No timetable found in Firestore, checking local storage', {'storage_type': 'firestore_fallback'});
          timetable = await _loadFromLocalStorage();
        }
      } else {
        // Guest user - load from local storage
        SecureLogger.info('DATA', 'Guest user - loading timetable from local storage', {'user_type': 'guest', 'storage_type': 'local'});
        timetable = await _loadFromLocalStorage();
      }

      // Create new timetable if none exists
      if (timetable == null) {
        SecureLogger.info('DATA', 'No existing timetable found, creating new one', {'operation': 'create_new'});
        timetable = await _createNewTimetable();
      }

      // Switch campus if needed
      if (CampusService.currentCampus != timetable.campus) {
        await CampusService.setCampus(timetable.campus);
        SecureLogger.info('DATA', 'Campus automatically switched to match timetable', {
          'new_campus': CampusService.getCampusDisplayName(timetable.campus),
          'operation': 'auto_switch_campus'
        });
      }

      // Load course data and update timetable
      final updatedTimetable = await _loadCourseDataForTimetable(timetable);

      state = state.copyWith(
        currentTimetable: updatedTimetable,
        isLoading: false,
        hasUnsavedChanges: false,
        error: null,
      );

    } catch (e) {
      SecureLogger.error('DATA', 'Error loading timetable', e, null, {'operation': 'load_timetable'});
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Save current timetable
  Future<void> saveTimetable() async {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return;

    state = state.copyWith(isSaving: true, error: null);

    try {
      // Update timestamp
      final updatedTimetable = Timetable(
        id: currentTimetable.id,
        name: currentTimetable.name,
        createdAt: currentTimetable.createdAt,
        updatedAt: DateTime.now(),
        campus: currentTimetable.campus,
        availableCourses: currentTimetable.availableCourses,
        selectedSections: currentTimetable.selectedSections,
        clashWarnings: currentTimetable.clashWarnings,
      );

      SecureLogger.dataOperation('save', 'timetable', true, {
        'timetable_name': updatedTimetable.name,
        'campus': CampusService.getCampusDisplayName(updatedTimetable.campus),
        'operation': 'save_timetable'
      });

      // Save to appropriate storage
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Saving timetable to Firestore', {'storage_type': 'firestore'});
        final success = await _firestoreService.saveTimetable(updatedTimetable);
        
        if (!success) {
          SecureLogger.warning('DATA', 'Failed to save to Firestore, falling back to local storage', {'storage_type': 'firestore_fallback'});
          await _saveToLocalStorage(updatedTimetable);
        }
      } else {
        SecureLogger.info('DATA', 'Guest user - saving timetable to local storage', {'user_type': 'guest', 'storage_type': 'local'});
        await _saveToLocalStorage(updatedTimetable);
      }

      state = state.copyWith(
        currentTimetable: updatedTimetable,
        isSaving: false,
        hasUnsavedChanges: false,
      );

    } catch (e) {
      SecureLogger.error('DATA', 'Error saving timetable', e, null, {'operation': 'save_timetable'});
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save timetable: ${e.toString()}',
      );
    }
  }

  /// Add section to current timetable
  Future<bool> addSection(String courseCode, String sectionId) async {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return false;

    try {
      final success = _addSectionToTimetable(courseCode, sectionId, currentTimetable);
      if (success) {
        await saveTimetable();
        return true;
      }
      return false;
    } catch (e) {
      SecureLogger.error('DATA', 'Error in addSection', e, null, {'operation': 'add_section'});
      state = state.copyWith(error: 'Failed to add section: ${e.toString()}');
      return false;
    }
  }

  /// Add section without saving (for batch operations)
  bool addSectionWithoutSaving(String courseCode, String sectionId) {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return false;

    try {
      final success = _addSectionToTimetable(courseCode, sectionId, currentTimetable);
      if (success) {
        state = state.copyWith(hasUnsavedChanges: true);
      }
      return success;
    } catch (e) {
      SecureLogger.error('DATA', 'Error in addSectionWithoutSaving', e, null, {'operation': 'add_section_no_save'});
      state = state.copyWith(error: 'Failed to add section: ${e.toString()}');
      return false;
    }
  }

  /// Remove section from current timetable
  Future<void> removeSection(String courseCode, String sectionId) async {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return;

    _removeSectionFromTimetable(courseCode, sectionId, currentTimetable);
    await saveTimetable();
  }

  /// Remove section without saving (for batch operations)
  void removeSectionWithoutSaving(String courseCode, String sectionId) {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return;

    _removeSectionFromTimetable(courseCode, sectionId, currentTimetable);
    state = state.copyWith(hasUnsavedChanges: true);
  }

  /// Clear all selected sections
  void clearAllSections() {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return;

    currentTimetable.selectedSections.clear();
    currentTimetable.clashWarnings.clear();
    
    state = state.copyWith(hasUnsavedChanges: true);
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Update timetable name
  void updateTimetableName(String name) {
    final currentTimetable = state.currentTimetable;
    if (currentTimetable == null) return;

    final updatedTimetable = Timetable(
      id: currentTimetable.id,
      name: name,
      createdAt: currentTimetable.createdAt,
      updatedAt: currentTimetable.updatedAt,
      campus: currentTimetable.campus,
      availableCourses: currentTimetable.availableCourses,
      selectedSections: currentTimetable.selectedSections,
      clashWarnings: currentTimetable.clashWarnings,
    );

    state = state.copyWith(
      currentTimetable: updatedTimetable,
      hasUnsavedChanges: true,
    );
  }

  // Private helper methods

  Future<Timetable?> _loadFromLocalStorage() async {
    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      
      if (data != null) {
        final json = jsonDecode(data);
        final timetable = Timetable.fromJson(json);
        SecureLogger.dataOperation('load', 'timetable_local', true, {'storage_type': 'local'});
        return timetable;
      }
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading from SharedPreferences', e, null, {'storage_type': 'local'});
      
      // Fallback to localStorage for web
      if (kIsWeb) {
        try {
          final data = js.context.callMethod('eval', ['window.localStorage.getItem("$_storageKey")']);
          if (data != null) {
            final json = jsonDecode(data);
            final timetable = Timetable.fromJson(json);
            SecureLogger.dataOperation('load', 'timetable_localStorage', true, {'storage_type': 'localStorage'});
            return timetable;
          }
        } catch (jsError) {
          SecureLogger.error('DATA', 'Error loading from localStorage', jsError, null, {'storage_type': 'localStorage'});
        }
      }
    }
    
    return null;
  }

  Future<void> _saveToLocalStorage(Timetable timetable) async {
    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(timetable.toJson());
      await prefs.setString(_storageKey, data);
      
      SecureLogger.dataOperation('save', 'timetable_local', true, {'storage_type': 'local'});
    } catch (e) {
      SecureLogger.error('DATA', 'Error saving timetable to local storage', e, null, {'storage_type': 'local'});
      
      // Fallback to localStorage for web
      if (kIsWeb) {
        try {
          final data = jsonEncode(timetable.toJson());
          js.context.callMethod('eval', [
            'window.localStorage.setItem("$_storageKey", \'$data\')'
          ]);
          SecureLogger.dataOperation('save', 'timetable_localStorage', true, {'storage_type': 'localStorage'});
        } catch (jsError) {
          SecureLogger.error('DATA', 'Error saving to localStorage', jsError, null, {'storage_type': 'localStorage'});
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<Timetable> _createNewTimetable() async {
    final now = DateTime.now();
    return Timetable(
      id: now.millisecondsSinceEpoch.toString(),
      name: 'My Timetable',
      createdAt: now,
      updatedAt: now,
      campus: CampusService.currentCampus,
      availableCourses: [],
      selectedSections: [],
      clashWarnings: [],
    );
  }

  Future<Timetable> _loadCourseDataForTimetable(Timetable timetable) async {
    try {
      final courses = await _courseDataService.fetchCourses();
      final clashWarnings = ClashDetector.detectClashes(timetable.selectedSections, courses);

      return Timetable(
        id: timetable.id,
        name: timetable.name,
        createdAt: timetable.createdAt,
        updatedAt: timetable.updatedAt,
        campus: timetable.campus,
        availableCourses: courses,
        selectedSections: timetable.selectedSections,
        clashWarnings: clashWarnings,
      );
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading course data for timetable', e, null, {'operation': 'load_course_data'});
      // Return original timetable if course loading fails
      return timetable;
    }
  }

  bool _addSectionToTimetable(String courseCode, String sectionId, Timetable timetable) {
    final course = timetable.availableCourses.firstWhere(
      (c) => c.courseCode == courseCode,
      orElse: () => throw Exception('Course not found: $courseCode'),
    );

    final section = course.sections.firstWhere(
      (s) => s.sectionId == sectionId,
      orElse: () => throw Exception('Section not found: $sectionId'),
    );

    // Check for existing section of same type for this course
    final existingSameType = timetable.selectedSections.where(
      (s) => s.courseCode == courseCode && s.section.type == section.type,
    );

    if (existingSameType.isNotEmpty) {
      // Replace existing section of same type
      timetable.selectedSections.removeWhere(
        (s) => s.courseCode == courseCode && s.section.type == section.type,
      );
    }

    final selectedSection = SelectedSection(
      courseCode: courseCode,
      sectionId: sectionId,
      section: section,
    );

    // Check for clashes
    final tempSelected = [...timetable.selectedSections, selectedSection];
    final clashes = ClashDetector.detectClashes(tempSelected, timetable.availableCourses);
    
    // Allow adding if no time clashes (exam clashes are warnings only)
    final hasTimeClash = clashes.any((clash) => clash.type == ClashType.regularClass);
    if (hasTimeClash) {
      return false;
    }

    timetable.selectedSections.add(selectedSection);
    timetable.clashWarnings.clear();
    timetable.clashWarnings.addAll(clashes);

    SecureLogger.dataOperation('add', 'section', true, {
      'course_code': courseCode,
      'section_id': sectionId,
      'section_type': section.type.toString(),
    });

    return true;
  }

  void _removeSectionFromTimetable(String courseCode, String sectionId, Timetable timetable) {
    timetable.selectedSections.removeWhere(
      (s) => s.courseCode == courseCode && s.sectionId == sectionId,
    );

    // Recalculate clashes after removal
    final clashes = ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses);
    timetable.clashWarnings.clear();
    timetable.clashWarnings.addAll(clashes);

    SecureLogger.dataOperation('remove', 'section', true, {
      'course_code': courseCode,
      'section_id': sectionId,
    });
  }
}

// Utility classes for timetable operations
class TimetableSlotGenerator {
  static List<TimetableSlot> generateSlots(
    List<SelectedSection> selectedSections, 
    List<Course> availableCourses, 
    {Campus? campus}
  ) {
    List<TimetableSlot> slots = [];
    
    for (var selectedSection in selectedSections) {
      // Find the course title with improved fallback
      String courseTitle = selectedSection.courseCode; // Default fallback
      
      try {
        final course = availableCourses.firstWhere(
          (c) => c.courseCode == selectedSection.courseCode,
        );
        courseTitle = course.courseTitle;
      } catch (e) {
        // Course not found in current semester - use course code as fallback
        courseTitle = selectedSection.courseCode;
      }
      
      // Use the schedule structure to handle different hours for different days
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          slots.add(TimetableSlot(
            day: day,
            hours: scheduleEntry.hours,
            courseCode: selectedSection.courseCode,
            courseTitle: courseTitle,
            sectionId: selectedSection.sectionId,
            instructor: selectedSection.section.instructor,
            room: selectedSection.section.room,
          ));
        }
      }
    }
    
    return slots;
  }
}

class TimetableValidator {
  static List<String> getIncompleteSelectionWarnings(
    List<SelectedSection> selectedSections, 
    List<Course> availableCourses
  ) {
    List<String> warnings = [];
    
    // Group selected sections by course code
    Map<String, List<SelectedSection>> courseSelections = {};
    for (var selection in selectedSections) {
      courseSelections[selection.courseCode] ??= [];
      courseSelections[selection.courseCode]!.add(selection);
    }
    
    // Check each course for missing required section types
    for (var courseCode in courseSelections.keys) {
      try {
        final course = availableCourses.firstWhere(
          (c) => c.courseCode == courseCode,
        );
        
        final selectedSectionTypes = courseSelections[courseCode]!
            .map((s) => s.section.type)
            .toSet();
            
        final availableSectionTypes = course.sections
            .map((s) => s.type)
            .toSet();
            
        // Check for missing required sections
        final missingTypes = <SectionType>[];
        
        // Check if lecture is required but missing
        if (availableSectionTypes.contains(SectionType.L) && 
            !selectedSectionTypes.contains(SectionType.L)) {
          missingTypes.add(SectionType.L);
        }
        
        // Check if practical is required but missing  
        if (availableSectionTypes.contains(SectionType.P) && 
            !selectedSectionTypes.contains(SectionType.P)) {
          missingTypes.add(SectionType.P);
        }
        
        // Check if tutorial is required but missing
        if (availableSectionTypes.contains(SectionType.T) && 
            !selectedSectionTypes.contains(SectionType.T)) {
          missingTypes.add(SectionType.T);
        }
        
        if (missingTypes.isNotEmpty) {
          final missingNames = missingTypes.map((type) => type.name).join(', ');
          warnings.add('$courseCode is missing: $missingNames sections');
        }
        
      } catch (e) {
        // Course not found in current semester
        warnings.add('$courseCode: Course not found in current semester');
      }
    }
    
    return warnings;
  }
}