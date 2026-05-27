import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/timetable.dart';
import '../../models/course.dart';
import 'clash_detector.dart';
import '../data/auth_service.dart';
import '../data/firestore_service.dart';
import '../data/course_data_service.dart';
import '../data/campus_service.dart';
import 'course_catalog_service.dart';
import '../ui/secure_logger.dart';

class TimetableService {
  static const String _storageKey = 'user_timetable_data';
  static const String _timetablesListKey = 'user_timetables_list';
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final CourseDataService _courseDataService = CourseDataService();
  final CourseCatalogService _allCourseService = CourseCatalogService();
  
  // Save timetable using Firestore for authenticated users or local storage for guests
  Future<void> saveTimetable(Timetable timetable) async {
    final perfSw = Stopwatch()..start();
    try {
      // Update the timetable's updatedAt timestamp
      final updatedTimetable = timetable.copyWith(
        updatedAt: DateTime.now(),
      );
      
      // If user is authenticated, save to Firestore
      if (_authService.isAuthenticated) {
        final success = await _firestoreService.saveTimetable(updatedTimetable);
        if (success) {
          // saved to Firestore
        } else {
          SecureLogger.error('TIMETABLE_SVC', 'Failed to save to Firestore, falling back to local storage');
          await saveTimetableToStorage(updatedTimetable);
        }
      } else {
        // Guest user - save to local storage using new format
        await saveTimetableToStorage(updatedTimetable);
      }
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error saving timetable: $e');
      // Fallback to local storage
      await saveTimetableToStorage(timetable);
    } finally {
      perfSw.stop();
      SecureLogger.performance('save_timetable', perfSw.elapsed);
    }
  }


  // Load timetable using Firestore for authenticated users or local storage for guests
  Future<Timetable> loadTimetable() async {
    try {
      Timetable? timetable;
      
      // If user is authenticated, try to load from Firestore
      if (_authService.isAuthenticated) {
        timetable = await _firestoreService.loadTimetable();
        timetable ??= await _loadFromLocalStorage();
      } else {
        // Guest user - load from local storage
        timetable = await _loadFromLocalStorage();
      }

      // If no timetable found, create a new one
      if (timetable == null) {
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
      }

      // Always check for updated courses from Firestore
      await _loadCoursesFromFirestore(timetable);

      return timetable;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error loading timetable: $e');
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

      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);

      if (data == null) {
        return null;
      } else {
        final jsonData = jsonDecode(data);
        return Timetable.fromJson(jsonData);
      }
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error loading timetable from local storage: $e');
      return null;
    }
  }

  Future<void> _loadCoursesFromFirestore(Timetable timetable) async {
    try {
      // Try to fetch courses directly without checking metadata first
      final courses = await _courseDataService.fetchCourses();

      if (courses.isEmpty) {
        throw Exception('No course data found in Firestore. Please ensure the upload script has been run successfully.');
      }

      // Clear existing courses before adding new ones
      timetable.availableCourses.clear();
      timetable.availableCourses.addAll(courses);

      await saveTimetable(timetable);
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error loading courses from Firestore: $e');
      
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
        await saveTimetable(timetable);
        return true;
      }
      return false;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error in addSection: $e');
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
        return true;
      }
      return false;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error in addSectionWithoutSaving: $e');
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
    final perfSw = Stopwatch()..start();
    try {
      List<Timetable> timetables = [];

      if (_authService.isAuthenticated) {
        timetables = await _firestoreService.getAllTimetables();
        if (timetables.isEmpty) {
          timetables = await _getAllTimetablesFromLocalStorage();
        }
      } else {
        timetables = await _getAllTimetablesFromLocalStorage();
      }

      // If no timetables exist, try to migrate from old format or create a default one
      if (timetables.isEmpty) {
        // Try to migrate from old timetable format
        final oldTimetable = await _migrateFromOldFormat();
        if (oldTimetable != null) {
          timetables.add(oldTimetable);
        } else {
          final defaultTimetable = await createNewTimetable("My Timetable");
          timetables.add(defaultTimetable);
        }
      }

      return timetables;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error getting all timetables: $e');
      // Return a default timetable if there's an error
      final defaultTimetable = await createNewTimetable("My Timetable");
      return [defaultTimetable];
    } finally {
      perfSw.stop();
      SecureLogger.performance('get_all_timetables', perfSw.elapsed);
    }
  }

  Future<List<Timetable>> _getAllTimetablesFromLocalStorage() async {
    try {

      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];

      List<Timetable> timetables = [];
      for (String id in timetableIds) {
        final data = prefs.getString('timetable_$id');
        if (data != null) {
          try {
            final jsonData = jsonDecode(data);
            final timetable = Timetable.fromJson(jsonData);
            timetables.add(timetable);
          } catch (e) {
            SecureLogger.error('TIMETABLE_SVC', 'Error parsing timetable $id: $e');
          }
        }
      }

      return timetables;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error loading timetables from local storage: $e');
      return [];
    }
  }

  Future<Timetable> createNewTimetable(String name) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    
    // Load available courses
    List<Course> courses = [];
    try {
      courses = await _courseDataService.fetchCourses();
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error loading courses for new timetable: $e');
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
        final success = await _firestoreService.saveTimetable(timetable);
        if (!success) {
          SecureLogger.error('TIMETABLE_SVC', 'Failed to save new timetable to Firestore, falling back to local storage');
          await saveTimetableToStorage(timetable);
          await _addTimetableToList(id);
        }
      } else {
        await saveTimetableToStorage(timetable);
        await _addTimetableToList(id);
      }

      // Verify it was saved properly
      final savedTimetable = await getTimetableById(id);
      if (savedTimetable == null) {
        SecureLogger.error('TIMETABLE_SVC', 'Verification failed: new timetable not found after save');
      }

    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error saving new timetable: $e');
      rethrow;
    }
    
    return timetable;
  }

  Future<void> saveTimetableToStorage(Timetable timetable) async {
    try {

      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(timetable.toJson());
      final key = 'timetable_${timetable.id}';

      await prefs.setString(key, data);

      // Verify it was saved
      final savedData = prefs.getString(key);
      if (savedData == null) {
        throw Exception('Failed to save timetable to storage');
      }
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error saving timetable to storage: $e');
      rethrow;
    }
  }

  Future<void> _addTimetableToList(String id) async {
    try {

      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];

      if (!timetableIds.contains(id)) {
        timetableIds.add(id);
        await prefs.setStringList(_timetablesListKey, timetableIds);
      }
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error adding timetable to list: $e');
    }
  }

  Future<Timetable?> getTimetableById(String id) async {
    try {
      if (_authService.isAuthenticated) {
        final timetable = await _firestoreService.getTimetableById(id);
        if (timetable != null) {
          // Set the campus to match the timetable's campus
          if (CampusService.currentCampus != timetable.campus) {
            await CampusService.setCampus(timetable.campus);
          }

          // Always check for updated courses from Firestore
          await _loadCoursesFromFirestore(timetable);

          return timetable;
        }
      }

      // Check local storage (for guests or as fallback)

      final prefs = await SharedPreferences.getInstance();
      final key = 'timetable_$id';
      final data = prefs.getString(key);

      if (data != null) {
        final jsonData = jsonDecode(data);
        final timetable = Timetable.fromJson(jsonData);

        // Set the campus to match the timetable's campus
        if (CampusService.currentCampus != timetable.campus) {
          await CampusService.setCampus(timetable.campus);
        }

        // Always check for updated courses from Firestore
        await _loadCoursesFromFirestore(timetable);

        return timetable;
      }

      return null;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error getting timetable by id: $e');
      return null;
    }
  }

  Future<void> deleteTimetable(String id) async {
    try {
      if (_authService.isAuthenticated) {
        final success = await _firestoreService.deleteTimetableById(id);
        if (!success) {
          SecureLogger.error('TIMETABLE_SVC', 'Failed to delete timetable from Firestore');
        }
      }

      // Also delete from local storage (for guests or as cleanup)
      
      final prefs = await SharedPreferences.getInstance();
      
      // Remove from storage
      await prefs.remove('timetable_$id');
      
      // Remove from list
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      timetableIds.remove(id);
      await prefs.setStringList(_timetablesListKey, timetableIds);
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error deleting timetable: $e');
    }
  }

  Future<Timetable> duplicateTimetable(Timetable sourceTimetable, String newName) async {
    final now = DateTime.now();
    final newId = now.millisecondsSinceEpoch.toString();
    
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
        final success = await _firestoreService.saveTimetable(duplicatedTimetable);
        if (!success) {
          SecureLogger.error('TIMETABLE_SVC', 'Failed to save duplicated timetable to Firestore, falling back to local storage');
          await saveTimetableToStorage(duplicatedTimetable);
          await _addTimetableToList(newId);
        }
      } else {
        await saveTimetableToStorage(duplicatedTimetable);
        await _addTimetableToList(newId);
      }

      // Verify it was saved properly
      final savedTimetable = await getTimetableById(newId);
      if (savedTimetable == null) {
        SecureLogger.error('TIMETABLE_SVC', 'Verification failed: duplicated timetable not found after save');
      }

    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error saving duplicated timetable: $e');
      rethrow;
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

      final prefs = await SharedPreferences.getInstance();
      final oldData = prefs.getString(_storageKey);

      if (oldData != null) {
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

          return migratedTimetable;
        }
      }

      return null;
    } catch (e) {
      SecureLogger.error('TIMETABLE_SVC', 'Error during migration: $e');
      return null;
    }
  }
}