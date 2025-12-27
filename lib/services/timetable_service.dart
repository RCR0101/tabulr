import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import 'clash_detector.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'course_data_service.dart';
import 'campus_service.dart';
import 'all_course_service.dart';
import 'secure_logger.dart';

class TimetableService {
  static const String _storageKey = 'user_timetable_data';
  static const String _timetablesListKey = 'user_timetables_list';
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final CourseDataService _courseDataService = CourseDataService();
  final AllCourseService _allCourseService = AllCourseService();
  
  // Save timetable using Firestore for authenticated users or local storage for guests
  Future<void> saveTimetable(Timetable timetable) async {
    try {
      // Update the timetable's updatedAt timestamp
      final updatedTimetable = Timetable(
        id: timetable.id,
        name: timetable.name,
        createdAt: timetable.createdAt,
        updatedAt: DateTime.now(),
        campus: timetable.campus,
        availableCourses: timetable.availableCourses,
        selectedSections: timetable.selectedSections,
        clashWarnings: timetable.clashWarnings,
      );
      
      SecureLogger.dataOperation('save', 'timetable', true, {
        'timetable_name': timetable.name,
        'campus': CampusService.getCampusDisplayName(timetable.campus),
        'operation': 'save_timetable'
      });
      
      // If user is authenticated, save to Firestore
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Saving timetable to Firestore', {'storage_type': 'firestore'});
        final success = await _firestoreService.saveTimetable(updatedTimetable);
        if (success) {
          SecureLogger.dataOperation('save', 'timetable_firestore', true, {'storage_type': 'firestore'});
        } else {
          SecureLogger.warning('DATA', 'Failed to save to Firestore, falling back to local storage', {'storage_type': 'firestore_fallback'});
          await saveTimetableToStorage(updatedTimetable);
        }
      } else {
        // Guest user - save to local storage using new format
        SecureLogger.info('DATA', 'Guest user - saving timetable to local storage', {'user_type': 'guest', 'storage_type': 'local'});
        await saveTimetableToStorage(updatedTimetable);
      }
    } catch (e) {
      SecureLogger.error('DATA', 'Error saving timetable', e, null, {'operation': 'save_timetable'});
      // Fallback to local storage
      await saveTimetableToStorage(timetable);
    }
  }

  // Helper method to save to local storage
  Future<void> _saveToLocalStorage(Timetable timetable) async {
    try {
      SecureLogger.info('DATA', 'Saving timetable to local storage', {'storage_type': 'local'});
      
      // Initialize SharedPreferences for web compatibility
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
      // In web, if SharedPreferences fails, let's use localStorage directly
      if (kIsWeb) {
        try {
          // Access localStorage through JavaScript interop
          final data = jsonEncode(timetable.toJson());
          js.context.callMethod('eval', [
            'window.localStorage.setItem("$_storageKey", \'$data\')'
          ]);
          SecureLogger.dataOperation('save', 'timetable_localStorage', true, {'storage_type': 'localStorage'});
        } catch (jsError) {
          SecureLogger.error('DATA', 'Error saving to localStorage', jsError, null, {'storage_type': 'localStorage'});
        }
      }
    }
  }

  // Load timetable using Firestore for authenticated users or local storage for guests
  Future<Timetable> loadTimetable() async {
    try {
      Timetable? timetable;
      
      // If user is authenticated, try to load from Firestore
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
      
      // If no timetable found, create a new one
      if (timetable == null) {
        SecureLogger.info('DATA', 'No existing timetable found, creating new one', {'operation': 'create_new'});
        final now = DateTime.now();
        timetable = Timetable(
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
      
      // Set the campus to match the timetable's campus
      if (CampusService.currentCampus != timetable.campus) {
        await CampusService.setCampus(timetable.campus);
        SecureLogger.info('DATA', 'Campus automatically switched to match timetable', {
          'new_campus': CampusService.getCampusDisplayName(timetable.campus),
          'operation': 'auto_switch_campus'
        });
      }
      
      // Always check for updated courses from Firestore
      await _loadCoursesFromFirestore(timetable);
      
      return timetable;
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading timetable', e, null, {'operation': 'load_timetable'});
      final now = DateTime.now();
      final timetable = Timetable(
        id: now.millisecondsSinceEpoch.toString(),
        name: 'My Timetable',
        createdAt: now,
        updatedAt: now,
        campus: CampusService.currentCampus,
        availableCourses: [],
        selectedSections: [],
        clashWarnings: [],
      );
      await _loadCoursesFromFirestore(timetable);
      return timetable;
    }
  }

  // Helper method to load from local storage
  Future<Timetable?> _loadFromLocalStorage() async {
    try {
      SecureLogger.info('DATA', 'Loading timetable from local storage', {'storage_type': 'local'});
      
      // Initialize SharedPreferences for web compatibility
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      
      if (data == null) {
        SecureLogger.info('DATA', 'No existing timetable found in local storage', {'storage_type': 'local'});
        return null;
      } else {
        SecureLogger.dataOperation('load', 'timetable_local', true, {'storage_type': 'local'});
        final jsonData = jsonDecode(data);
        return Timetable.fromJson(jsonData);
      }
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading timetable from local storage', e, null, {'storage_type': 'local'});
      return null;
    }
  }

  Future<void> _loadCoursesFromFirestore(Timetable timetable) async {
    try {
      SecureLogger.info('DATA', 'Attempting to load courses from Firestore', {'operation': 'load_courses'});
      
      // Try to fetch courses directly without checking metadata first
      final courses = await _courseDataService.fetchCourses();
      
      if (courses.isEmpty) {
        SecureLogger.warning('DATA', 'No courses found in Firestore. This might be a configuration issue.', {'course_count': 0});
        throw Exception('No course data found in Firestore. Please ensure the upload script has been run successfully.');
      }
      
      SecureLogger.dataOperation('load', 'courses_firestore', true, {'course_count': courses.length});
      
      // Clear existing courses before adding new ones
      timetable.availableCourses.clear();
      timetable.availableCourses.addAll(courses);
      
      if (courses.isNotEmpty) {
        SecureLogger.debug('DATA', 'First course loaded', {
          'course_code': courses.first.courseCode,
          'course_title': courses.first.courseTitle
        });
      }
      
      await saveTimetable(timetable);
      SecureLogger.dataOperation('save', 'timetable_with_courses', true, {'operation': 'save_with_courses'});
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading courses from Firestore', e, null, {'operation': 'load_courses'});
      
      // Show a more user-friendly error message
      String userMessage = 'Failed to load course data.';
      if (e.toString().contains('Permission denied')) {
        userMessage = 'Access denied to course data. Please check your internet connection and try again.';
      } else if (e.toString().contains('Network connection error')) {
        userMessage = 'Network connection error. Please check your internet connection and try again.';
      } else if (e.toString().contains('No course data found')) {
        userMessage = 'Course data is not available. Please contact the administrator.';
      }
      
      throw Exception(userMessage);
    }
  }

  Future<bool> addSection(String courseCode, String sectionId, Timetable timetable) async {
    try {
      SecureLogger.info('DATA', 'Attempting to add section', {
        'course_code': courseCode,
        'section_id': sectionId,
        'operation': 'add_section'
      });
      
      final course = timetable.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );
      SecureLogger.debug('DATA', 'Found course', {'course_code': course.courseCode});

      final section = course.sections.firstWhere(
        (s) => s.sectionId == sectionId,
        orElse: () => throw Exception('Section not found: $sectionId'),
      );
      SecureLogger.debug('DATA', 'Found section', {'section_id': section.sectionId});

      final newSelection = SelectedSection(
        courseCode: courseCode,
        sectionId: sectionId,
        section: section,
      );

      SecureLogger.info('DATA', 'Checking for clashes', {'operation': 'clash_detection'});
      if (ClashDetector.canAddSection(newSelection, timetable.selectedSections, timetable.availableCourses)) {
        SecureLogger.info('DATA', 'No clashes found, adding section', {'operation': 'add_section_success'});
        timetable.selectedSections.add(newSelection);
        timetable.clashWarnings.clear();
        timetable.clashWarnings.addAll(
          ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses)
        );
        SecureLogger.info('DATA', 'Saving timetable after adding section', {'operation': 'save_after_add'});
        await saveTimetable(timetable);
        SecureLogger.dataOperation('add', 'section', true, {'operation': 'section_added'});
        return true;
      } else {
        SecureLogger.warning('DATA', 'Clash detected, cannot add section', {'operation': 'add_section_clash'});
      }
      return false;
    } catch (e) {
      SecureLogger.error('DATA', 'Error in addSection', e, null, {'operation': 'add_section'});
      rethrow;
    }
  }

  Future<void> removeSection(String courseCode, String sectionId, Timetable timetable) async {
    timetable.selectedSections.removeWhere(
      (s) => s.courseCode == courseCode && s.sectionId == sectionId,
    );
    timetable.clashWarnings.clear();
    timetable.clashWarnings.addAll(
      ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses)
    );
    await saveTimetable(timetable);
  }

  // Non-saving versions for manual save functionality
  bool addSectionWithoutSaving(String courseCode, String sectionId, Timetable timetable) {
    try {
      SecureLogger.info('DATA', 'Attempting to add section without saving', {
        'course_code': courseCode,
        'section_id': sectionId,
        'operation': 'add_section_no_save'
      });
      
      final course = timetable.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );

      final section = course.sections.firstWhere(
        (s) => s.sectionId == sectionId,
        orElse: () => throw Exception('Section not found: $sectionId'),
      );

      final newSelection = SelectedSection(
        courseCode: courseCode,
        sectionId: sectionId,
        section: section,
      );

      if (ClashDetector.canAddSection(newSelection, timetable.selectedSections, timetable.availableCourses)) {
        timetable.selectedSections.add(newSelection);
        timetable.clashWarnings.clear();
        timetable.clashWarnings.addAll(
          ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses)
        );
        SecureLogger.info('DATA', 'Section added successfully without saving', {'operation': 'add_section_no_save_success'});
        return true;
      } else {
        SecureLogger.warning('DATA', 'Clash detected, cannot add section', {'operation': 'add_section_clash'});
      }
      return false;
    } catch (e) {
      SecureLogger.error('DATA', 'Error in addSectionWithoutSaving', e, null, {'operation': 'add_section_no_save'});
      rethrow;
    }
  }

  void removeSectionWithoutSaving(String courseCode, String sectionId, Timetable timetable) {
    timetable.selectedSections.removeWhere(
      (s) => s.courseCode == courseCode && s.sectionId == sectionId,
    );
    timetable.clashWarnings.clear();
    timetable.clashWarnings.addAll(
      ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses)
    );
  }

  List<TimetableSlot> generateTimetableSlots(List<SelectedSection> selectedSections, List<Course> availableCourses, {Campus? campus}) {
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
        // Course not found in current semester
        // Try to get from cache or use course code as fallback
        final cachedTitle = _allCourseService.getCachedCourseTitle(selectedSection.courseCode, campus: campus);
        if (cachedTitle != null) {
          courseTitle = cachedTitle;
        }
        // If no cached title, courseTitle remains as courseCode (better than 'Unknown Course')
      }
      
      // Use the new schedule structure to handle different hours for different days
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

  // Check for incomplete course selections (missing L, P, or T sections)
  List<String> getIncompleteSelectionWarnings(List<SelectedSection> selectedSections, List<Course> availableCourses) {
    List<String> warnings = [];
    
    // Group selected sections by course code
    Map<String, List<SelectedSection>> courseSelections = {};
    for (var selection in selectedSections) {
      courseSelections[selection.courseCode] ??= [];
      courseSelections[selection.courseCode]!.add(selection);
    }
    
    // Check each course for missing section types
    for (var entry in courseSelections.entries) {
      final courseCode = entry.key;
      final selections = entry.value;
      
      // Find the course to see what sections are available
      final course = availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(courseCode: courseCode, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
      );
      
      if (course.sections.isEmpty) continue;
      
      // Check what section types are available for this course
      final availableSectionTypes = course.sections.map((s) => s.type).toSet();
      
      // Check what section types are selected
      final selectedSectionTypes = selections.map((s) => s.section.type).toSet();
      
      // Find missing section types
      final missingSectionTypes = availableSectionTypes.difference(selectedSectionTypes);
      
      for (var missingType in missingSectionTypes) {
        warnings.add('$courseCode ${missingType.name} not selected');
      }
    }
    
    return warnings;
  }

  // Multiple timetables functionality
  Future<List<Timetable>> getAllTimetables() async {
    try {
      SecureLogger.info('DATA', 'Getting all timetables', {'operation': 'get_all_timetables'});
      List<Timetable> timetables = [];
      
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'User is authenticated, loading from Firestore', {'user_type': 'authenticated', 'storage_type': 'firestore'});
        timetables = await _firestoreService.getAllTimetables();
        if (timetables.isEmpty) {
          SecureLogger.info('DATA', 'No timetables found in Firestore, checking local storage', {'storage_type': 'firestore_fallback'});
          timetables = await _getAllTimetablesFromLocalStorage();
        }
      } else {
        SecureLogger.info('DATA', 'User is guest, using local storage', {'user_type': 'guest', 'storage_type': 'local'});
        timetables = await _getAllTimetablesFromLocalStorage();
      }
      
      SecureLogger.dataOperation('load', 'timetables', true, {'timetable_count': timetables.length});
      
      // If no timetables exist, try to migrate from old format or create a default one
      if (timetables.isEmpty) {
        SecureLogger.info('DATA', 'No timetables found, attempting migration or creating default', {'operation': 'migration_or_default'});
        // Try to migrate from old timetable format
        final oldTimetable = await _migrateFromOldFormat();
        if (oldTimetable != null) {
          SecureLogger.dataOperation('migrate', 'timetable', true, {'operation': 'migration_success'});
          timetables.add(oldTimetable);
        } else {
          SecureLogger.info('DATA', 'No migration data, creating default timetable', {'operation': 'create_default'});
          final defaultTimetable = await createNewTimetable("My Timetable");
          timetables.add(defaultTimetable);
        }
      }
      
      return timetables;
    } catch (e) {
      SecureLogger.error('DATA', 'Error getting all timetables', e, null, {'operation': 'get_all_timetables'});
      // Return a default timetable if there's an error
      final defaultTimetable = await createNewTimetable("My Timetable");
      return [defaultTimetable];
    }
  }

  Future<List<Timetable>> _getAllTimetablesFromLocalStorage() async {
    try {
      SecureLogger.info('DATA', 'Loading timetables from local storage', {'storage_type': 'local'});
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      
      SecureLogger.debug('DATA', 'Timetable IDs from list', {'timetable_ids': timetableIds.toString()});
      
      List<Timetable> timetables = [];
      for (String id in timetableIds) {
        SecureLogger.debug('DATA', 'Loading timetable with id', {'timetable_id': id});
        final data = prefs.getString('timetable_$id');
        if (data != null) {
          try {
            final jsonData = jsonDecode(data);
            final timetable = Timetable.fromJson(jsonData);
            timetables.add(timetable);
            SecureLogger.dataOperation('load', 'timetable_local', true, {
              'timetable_name': timetable.name,
              'timetable_id': id
            });
          } catch (e) {
            SecureLogger.error('PARSE', 'Error parsing timetable', e, null, {'timetable_id': id});
          }
        } else {
          SecureLogger.warning('DATA', 'No data found for timetable', {'timetable_id': id});
        }
      }
      
      SecureLogger.dataOperation('load', 'timetables_local', true, {'total_count': timetables.length});
      return timetables;
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading timetables from local storage', e, null, {'storage_type': 'local'});
      return [];
    }
  }

  Future<Timetable> createNewTimetable(String name) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    
    SecureLogger.info('DATA', 'Creating new timetable', {
      'timetable_id': id,
      'timetable_name': name,
      'operation': 'create_new'
    });
    
    // Load available courses
    List<Course> courses = [];
    try {
      courses = await _courseDataService.fetchCourses();
      SecureLogger.dataOperation('load', 'courses_for_new_timetable', true, {'course_count': courses.length});
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading courses for new timetable', e, null, {'operation': 'load_courses_new_timetable'});
    }
    
    final timetable = Timetable(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      campus: CampusService.currentCampus,
      availableCourses: courses,
      selectedSections: [],
      clashWarnings: [],
    );
    
    try {
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Saving new timetable to Firestore', {'storage_type': 'firestore'});
        final success = await _firestoreService.saveTimetable(timetable);
        if (success) {
          SecureLogger.dataOperation('save', 'timetable_firestore', true, {'storage_type': 'firestore'});
        } else {
          SecureLogger.warning('DATA', 'Failed to save to Firestore, falling back to local storage', {'storage_type': 'firestore_fallback'});
          await saveTimetableToStorage(timetable);
          await _addTimetableToList(id);
        }
      } else {
        SecureLogger.info('DATA', 'Guest user - saving to local storage', {'user_type': 'guest', 'storage_type': 'local'});
        await saveTimetableToStorage(timetable);
        await _addTimetableToList(id);
      }
      
      // Verify it was saved properly
      final savedTimetable = await getTimetableById(id);
      if (savedTimetable != null) {
        SecureLogger.dataOperation('verify', 'new_timetable', true, {'operation': 'verification_success'});
      } else {
        SecureLogger.error('DATA', 'Verification: Failed to save timetable', null, null, {'operation': 'verification_failed'});
      }
      
    } catch (e) {
      SecureLogger.error('DATA', 'Error saving new timetable', e, null, {'operation': 'save_new_timetable'});
      throw e;
    }
    
    return timetable;
  }

  Future<void> saveTimetableToStorage(Timetable timetable) async {
    try {
      SecureLogger.info('DATA', 'Saving timetable to storage', {
        'timetable_id': timetable.id,
        'operation': 'save_to_storage'
      });
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(timetable.toJson());
      final key = 'timetable_${timetable.id}';
      
      SecureLogger.debug('DATA', 'Saving with key', {'storage_key': key});
      await prefs.setString(key, data);
      
      // Verify it was saved
      final savedData = prefs.getString(key);
      if (savedData != null) {
        SecureLogger.dataOperation('save', 'timetable_storage', true, {'storage_key': key});
      } else {
        SecureLogger.error('DATA', 'Failed to save timetable to storage - verification failed', null, null, {'storage_key': key});
        throw Exception('Failed to save timetable to storage');
      }
    } catch (e) {
      SecureLogger.error('DATA', 'Error saving timetable to storage', e, null, {'operation': 'save_to_storage'});
      rethrow;
    }
  }

  Future<void> _addTimetableToList(String id) async {
    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      
      if (!timetableIds.contains(id)) {
        timetableIds.add(id);
        await prefs.setStringList(_timetablesListKey, timetableIds);
      }
    } catch (e) {
      SecureLogger.error('DATA', 'Error adding timetable to list', e, null, {'operation': 'add_to_list'});
    }
  }

  Future<Timetable?> getTimetableById(String id) async {
    try {
      SecureLogger.info('DATA', 'Getting timetable by id', {
        'timetable_id': id,
        'operation': 'get_by_id'
      });
      
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'User is authenticated, checking Firestore first', {'user_type': 'authenticated', 'storage_type': 'firestore'});
        final timetable = await _firestoreService.getTimetableById(id);
        if (timetable != null) {
          SecureLogger.dataOperation('load', 'timetable_firestore', true, {
            'timetable_name': timetable.name,
            'timetable_id': id
          });
          
          // Set the campus to match the timetable's campus
          if (CampusService.currentCampus != timetable.campus) {
            await CampusService.setCampus(timetable.campus);
            SecureLogger.info('DATA', 'Campus automatically switched to match timetable', {
          'new_campus': CampusService.getCampusDisplayName(timetable.campus),
          'operation': 'auto_switch_campus'
        });
          }
          
          // Always check for updated courses from Firestore
          await _loadCoursesFromFirestore(timetable);
          
          return timetable;
        }
        SecureLogger.info('DATA', 'Timetable not found in Firestore, checking local storage', {'storage_type': 'firestore_fallback'});
      }
      
      // Check local storage (for guests or as fallback)
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final key = 'timetable_$id';
      final data = prefs.getString(key);
      
      SecureLogger.debug('DATA', 'Looking for key in local storage', {'storage_key': key});
      if (data != null) {
        SecureLogger.info('DATA', 'Found timetable data, parsing', {'storage_key': key});
        final jsonData = jsonDecode(data);
        final timetable = Timetable.fromJson(jsonData);
        SecureLogger.dataOperation('parse', 'timetable_local', true, {
          'timetable_name': timetable.name,
          'timetable_id': id
        });
        
        // Set the campus to match the timetable's campus
        if (CampusService.currentCampus != timetable.campus) {
          await CampusService.setCampus(timetable.campus);
          SecureLogger.info('DATA', 'Campus automatically switched to match timetable', {
          'new_campus': CampusService.getCampusDisplayName(timetable.campus),
          'operation': 'auto_switch_campus'
        });
        }
        
        // Always check for updated courses from Firestore
        await _loadCoursesFromFirestore(timetable);
        
        return timetable;
      } else {
        SecureLogger.warning('DATA', 'No data found for key', {'storage_key': key});
        
        // Debug: List all keys to see what's actually stored
        final allKeys = prefs.getKeys();
        SecureLogger.debug('DATA', 'All stored keys for debugging', {'all_keys': allKeys.toString()});
      }
      
      return null;
    } catch (e) {
      SecureLogger.error('DATA', 'Error getting timetable by id', e, null, {'timetable_id': id});
      return null;
    }
  }

  Future<void> deleteTimetable(String id) async {
    try {
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Deleting timetable from Firestore', {'storage_type': 'firestore'});
        final success = await _firestoreService.deleteTimetableById(id);
        if (!success) {
          SecureLogger.warning('DATA', 'Failed to delete from Firestore, deleting from local storage', {'storage_type': 'firestore_fallback'});
        }
      }
      
      // Also delete from local storage (for guests or as cleanup)
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Remove from storage
      await prefs.remove('timetable_$id');
      
      // Remove from list
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      timetableIds.remove(id);
      await prefs.setStringList(_timetablesListKey, timetableIds);
    } catch (e) {
      SecureLogger.error('DATA', 'Error deleting timetable', e, null, {'operation': 'delete_timetable'});
    }
  }

  Future<Timetable> duplicateTimetable(Timetable sourceTimetable, String newName) async {
    final now = DateTime.now();
    final newId = now.millisecondsSinceEpoch.toString();
    
    SecureLogger.info('DATA', 'Duplicating timetable', {
      'source_name': sourceTimetable.name,
      'new_name': newName,
      'new_id': newId,
      'operation': 'duplicate_timetable'
    });
    
    final duplicatedTimetable = Timetable(
      id: newId,
      name: newName,
      createdAt: now,
      updatedAt: now,
      campus: sourceTimetable.campus,
      availableCourses: sourceTimetable.availableCourses
          .map((course) => Course.fromJson(course.toJson()))
          .toList(),
      selectedSections: sourceTimetable.selectedSections
          .map((section) => SelectedSection.fromJson(section.toJson()))
          .toList(),
      clashWarnings: sourceTimetable.clashWarnings
          .map((warning) => ClashWarning.fromJson(warning.toJson()))
          .toList(),
    );
    
    try {
      if (_authService.isAuthenticated) {
        SecureLogger.info('DATA', 'Saving duplicated timetable to Firestore', {'storage_type': 'firestore'});
        final success = await _firestoreService.saveTimetable(duplicatedTimetable);
        if (success) {
          SecureLogger.dataOperation('save', 'duplicated_timetable_firestore', true, {'storage_type': 'firestore'});
        } else {
          SecureLogger.warning('DATA', 'Failed to save to Firestore, falling back to local storage', {'storage_type': 'firestore_fallback'});
          await saveTimetableToStorage(duplicatedTimetable);
          await _addTimetableToList(newId);
        }
      } else {
        SecureLogger.info('DATA', 'Guest user - saving duplicated timetable to local storage', {'user_type': 'guest', 'storage_type': 'local'});
        await saveTimetableToStorage(duplicatedTimetable);
        await _addTimetableToList(newId);
      }
      
      // Verify it was saved properly
      final savedTimetable = await getTimetableById(newId);
      if (savedTimetable != null) {
        SecureLogger.dataOperation('verify', 'duplicated_timetable', true, {'operation': 'verification_success'});
      } else {
        SecureLogger.error('DATA', 'Verification: Failed to save duplicated timetable', null, null, {'operation': 'verification_failed'});
      }
      
    } catch (e) {
      SecureLogger.error('DATA', 'Error saving duplicated timetable', e, null, {'operation': 'save_duplicated_timetable'});
      throw e;
    }
    
    return duplicatedTimetable;
  }

  Future<void> updateTimetableName(String id, String newName) async {
    final timetable = await getTimetableById(id);
    if (timetable != null) {
      final updatedTimetable = Timetable(
        id: timetable.id,
        name: newName,
        createdAt: timetable.createdAt,
        updatedAt: DateTime.now(),
        campus: timetable.campus,
        availableCourses: timetable.availableCourses,
        selectedSections: timetable.selectedSections,
        clashWarnings: timetable.clashWarnings,
      );
      
      await saveTimetable(updatedTimetable);
    }
  }

  // Migration method to convert old timetable format to new format
  Future<Timetable?> _migrateFromOldFormat() async {
    try {
      SecureLogger.info('DATA', 'Attempting to migrate from old timetable format', {'operation': 'migration'});
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          SecureLogger.debug('DATA', 'Mock values already set or not needed', {'error': e.toString()});
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final oldData = prefs.getString(_storageKey);
      
      if (oldData != null) {
        SecureLogger.info('DATA', 'Found old timetable data, migrating', {'operation': 'migration_start'});
        final jsonData = jsonDecode(oldData);
        
        // Check if this is old format (missing id, name, etc.)
        if (jsonData['id'] == null) {
          final now = DateTime.now();
          final id = now.millisecondsSinceEpoch.toString();
          
          // Create new timetable with old data
          final migratedTimetable = Timetable(
            id: id,
            name: 'My Timetable',
            createdAt: now,
            updatedAt: now,
            campus: Campus.hyderabad, // Default to hyderabad for migration
            availableCourses: (jsonData['availableCourses'] as List)
                .map((c) => Course.fromJson(c))
                .toList(),
            selectedSections: (jsonData['selectedSections'] as List)
                .map((s) => SelectedSection.fromJson(s))
                .toList(),
            clashWarnings: (jsonData['clashWarnings'] as List)
                .map((w) => ClashWarning.fromJson(w))
                .toList(),
          );
          
          // Save to new format
          await saveTimetableToStorage(migratedTimetable);
          await _addTimetableToList(id);
          
          // Remove old format
          await prefs.remove(_storageKey);
          
          SecureLogger.dataOperation('migrate', 'old_timetable_format', true, {'operation': 'migration_completed'});
          return migratedTimetable;
        }
      }
      
      SecureLogger.info('DATA', 'No old format timetable found', {'operation': 'no_migration_needed'});
      return null;
    } catch (e) {
      SecureLogger.error('DATA', 'Error during migration', e, null, {'operation': 'migration_error'});
      return null;
    }
  }
}