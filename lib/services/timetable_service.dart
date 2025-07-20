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

class TimetableService {
  static const String _storageKey = 'user_timetable_data';
  static const String _timetablesListKey = 'user_timetables_list';
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final CourseDataService _courseDataService = CourseDataService();
  
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
      
      print('Saving timetable "${timetable.name}" with campus: ${CampusService.getCampusDisplayName(timetable.campus)}');
      
      // If user is authenticated, save to Firestore
      if (_authService.isAuthenticated) {
        print('Saving timetable to Firestore...');
        final success = await _firestoreService.saveTimetable(updatedTimetable);
        if (success) {
          print('Timetable saved successfully to Firestore');
        } else {
          print('Failed to save to Firestore, falling back to local storage');
          await saveTimetableToStorage(updatedTimetable);
        }
      } else {
        // Guest user - save to local storage using new format
        print('Guest user - saving timetable to local storage...');
        await saveTimetableToStorage(updatedTimetable);
      }
    } catch (e) {
      print('Error saving timetable: $e');
      // Fallback to local storage
      await saveTimetableToStorage(timetable);
    }
  }

  // Helper method to save to local storage
  Future<void> _saveToLocalStorage(Timetable timetable) async {
    try {
      print('Saving timetable to local storage...');
      
      // Initialize SharedPreferences for web compatibility
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(timetable.toJson());
      
      await prefs.setString(_storageKey, data);
      
      print('Timetable saved successfully to local storage');
    } catch (e) {
      print('Error saving timetable to local storage: $e');
      // In web, if SharedPreferences fails, let's use localStorage directly
      if (kIsWeb) {
        try {
          // Access localStorage through JavaScript interop
          final data = jsonEncode(timetable.toJson());
          js.context.callMethod('eval', [
            'window.localStorage.setItem("$_storageKey", \'$data\')'
          ]);
          print('Saved to localStorage directly');
        } catch (jsError) {
          print('Error saving to localStorage: $jsError');
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
        print('Loading timetable from Firestore...');
        timetable = await _firestoreService.loadTimetable();
        if (timetable != null) {
          print('Timetable loaded successfully from Firestore');
        } else {
          print('No timetable found in Firestore, checking local storage...');
          timetable = await _loadFromLocalStorage();
        }
      } else {
        // Guest user - load from local storage
        print('Guest user - loading timetable from local storage...');
        timetable = await _loadFromLocalStorage();
      }
      
      // If no timetable found, create a new one
      if (timetable == null) {
        print('No existing timetable found, creating new one');
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
        print('Campus automatically switched to ${CampusService.getCampusDisplayName(timetable.campus)} to match timetable');
      }
      
      // Always check for updated courses from Firestore
      await _loadCoursesFromFirestore(timetable);
      
      return timetable;
    } catch (e) {
      print('Error loading timetable: $e');
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
      print('Loading timetable from local storage...');
      
      // Initialize SharedPreferences for web compatibility
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      
      if (data == null) {
        print('No existing timetable found in local storage');
        return null;
      } else {
        print('Found existing timetable data in local storage');
        final jsonData = jsonDecode(data);
        return Timetable.fromJson(jsonData);
      }
    } catch (e) {
      print('Error loading timetable from local storage: $e');
      return null;
    }
  }

  Future<void> _loadCoursesFromFirestore(Timetable timetable) async {
    try {
      print('Attempting to load courses from Firestore...');
      
      // Try to fetch courses directly without checking metadata first
      final courses = await _courseDataService.fetchCourses();
      
      if (courses.isEmpty) {
        print('No courses found in Firestore. This might be a configuration issue.');
        throw Exception('No course data found in Firestore. Please ensure the upload script has been run successfully.');
      }
      
      print('Loaded ${courses.length} courses from Firestore');
      
      // Clear existing courses before adding new ones
      timetable.availableCourses.clear();
      timetable.availableCourses.addAll(courses);
      
      if (courses.isNotEmpty) {
        print('First course: ${courses.first.courseCode} - ${courses.first.courseTitle}');
      }
      
      await saveTimetable(timetable);
      print('Saved timetable with Firestore courses');
    } catch (e) {
      print('Error loading courses from Firestore: $e');
      
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
      print('Attempting to add section: $courseCode - $sectionId');
      
      final course = timetable.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );
      print('Found course: ${course.courseCode}');

      final section = course.sections.firstWhere(
        (s) => s.sectionId == sectionId,
        orElse: () => throw Exception('Section not found: $sectionId'),
      );
      print('Found section: ${section.sectionId}');

      final newSelection = SelectedSection(
        courseCode: courseCode,
        sectionId: sectionId,
        section: section,
      );

      print('Checking for clashes...');
      if (ClashDetector.canAddSection(newSelection, timetable.selectedSections, timetable.availableCourses)) {
        print('No clashes found, adding section');
        timetable.selectedSections.add(newSelection);
        timetable.clashWarnings.clear();
        timetable.clashWarnings.addAll(
          ClashDetector.detectClashes(timetable.selectedSections, timetable.availableCourses)
        );
        print('Saving timetable...');
        await saveTimetable(timetable);
        print('Section added successfully');
        return true;
      } else {
        print('Clash detected, cannot add section');
      }
      return false;
    } catch (e) {
      print('Error in addSection: $e');
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
      print('Attempting to add section (no save): $courseCode - $sectionId');
      
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
        print('Section added successfully (no save)');
        return true;
      } else {
        print('Clash detected, cannot add section');
      }
      return false;
    } catch (e) {
      print('Error in addSectionWithoutSaving: $e');
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

  List<TimetableSlot> generateTimetableSlots(List<SelectedSection> selectedSections, List<Course> availableCourses) {
    List<TimetableSlot> slots = [];
    
    for (var selectedSection in selectedSections) {
      // Find the course title
      final course = availableCourses.firstWhere(
        (c) => c.courseCode == selectedSection.courseCode,
        orElse: () => Course(
          courseCode: selectedSection.courseCode,
          courseTitle: 'Unknown Course',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 0,
          sections: [],
        ),
      );
      
      // Use the new schedule structure to handle different hours for different days
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          slots.add(TimetableSlot(
            day: day,
            hours: scheduleEntry.hours,
            courseCode: selectedSection.courseCode,
            courseTitle: course.courseTitle,
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
      print('Getting all timetables...');
      List<Timetable> timetables = [];
      
      if (_authService.isAuthenticated) {
        print('User is authenticated, loading from Firestore...');
        timetables = await _firestoreService.getAllTimetables();
        if (timetables.isEmpty) {
          print('No timetables found in Firestore, checking local storage...');
          timetables = await _getAllTimetablesFromLocalStorage();
        }
      } else {
        print('User is guest, using local storage');
        timetables = await _getAllTimetablesFromLocalStorage();
      }
      
      print('Found ${timetables.length} timetables from storage');
      
      // If no timetables exist, try to migrate from old format or create a default one
      if (timetables.isEmpty) {
        print('No timetables found, attempting migration or creating default');
        // Try to migrate from old timetable format
        final oldTimetable = await _migrateFromOldFormat();
        if (oldTimetable != null) {
          print('Migration successful, using migrated timetable');
          timetables.add(oldTimetable);
        } else {
          print('No migration data, creating default timetable');
          final defaultTimetable = await createNewTimetable("My Timetable");
          timetables.add(defaultTimetable);
        }
      }
      
      return timetables;
    } catch (e) {
      print('Error getting all timetables: $e');
      // Return a default timetable if there's an error
      final defaultTimetable = await createNewTimetable("My Timetable");
      return [defaultTimetable];
    }
  }

  Future<List<Timetable>> _getAllTimetablesFromLocalStorage() async {
    try {
      print('Loading timetables from local storage...');
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      
      print('Timetable IDs from list: $timetableIds');
      
      List<Timetable> timetables = [];
      for (String id in timetableIds) {
        print('Loading timetable with id: $id');
        final data = prefs.getString('timetable_$id');
        if (data != null) {
          try {
            final jsonData = jsonDecode(data);
            final timetable = Timetable.fromJson(jsonData);
            timetables.add(timetable);
            print('Successfully loaded timetable: ${timetable.name}');
          } catch (e) {
            print('Error parsing timetable $id: $e');
          }
        } else {
          print('No data found for timetable $id');
        }
      }
      
      print('Total timetables loaded: ${timetables.length}');
      return timetables;
    } catch (e) {
      print('Error loading timetables from local storage: $e');
      return [];
    }
  }

  Future<Timetable> createNewTimetable(String name) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    
    print('Creating new timetable with id: $id, name: $name');
    
    // Load available courses
    List<Course> courses = [];
    try {
      courses = await _courseDataService.fetchCourses();
      print('Loaded ${courses.length} courses for new timetable');
    } catch (e) {
      print('Error loading courses for new timetable: $e');
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
        print('Saving new timetable to Firestore...');
        final success = await _firestoreService.saveTimetable(timetable);
        if (success) {
          print('Timetable saved successfully to Firestore');
        } else {
          print('Failed to save to Firestore, falling back to local storage');
          await saveTimetableToStorage(timetable);
          await _addTimetableToList(id);
        }
      } else {
        print('Guest user - saving to local storage');
        await saveTimetableToStorage(timetable);
        await _addTimetableToList(id);
      }
      
      // Verify it was saved properly
      final savedTimetable = await getTimetableById(id);
      if (savedTimetable != null) {
        print('Verification: Timetable saved successfully');
      } else {
        print('Verification: Failed to save timetable');
      }
      
    } catch (e) {
      print('Error saving new timetable: $e');
      throw e;
    }
    
    return timetable;
  }

  Future<void> saveTimetableToStorage(Timetable timetable) async {
    try {
      print('Saving timetable ${timetable.id} to storage...');
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(timetable.toJson());
      final key = 'timetable_${timetable.id}';
      
      print('Saving with key: $key');
      await prefs.setString(key, data);
      
      // Verify it was saved
      final savedData = prefs.getString(key);
      if (savedData != null) {
        print('Successfully saved timetable to storage');
      } else {
        print('Failed to save timetable to storage - verification failed');
        throw Exception('Failed to save timetable to storage');
      }
    } catch (e) {
      print('Error saving timetable to storage: $e');
      rethrow;
    }
  }

  Future<void> _addTimetableToList(String id) async {
    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final timetableIds = prefs.getStringList(_timetablesListKey) ?? [];
      
      if (!timetableIds.contains(id)) {
        timetableIds.add(id);
        await prefs.setStringList(_timetablesListKey, timetableIds);
      }
    } catch (e) {
      print('Error adding timetable to list: $e');
    }
  }

  Future<Timetable?> getTimetableById(String id) async {
    try {
      print('Getting timetable by id: $id');
      
      if (_authService.isAuthenticated) {
        print('User is authenticated, checking Firestore first...');
        final timetable = await _firestoreService.getTimetableById(id);
        if (timetable != null) {
          print('Found timetable in Firestore: ${timetable.name}');
          
          // Set the campus to match the timetable's campus
          if (CampusService.currentCampus != timetable.campus) {
            await CampusService.setCampus(timetable.campus);
            print('Campus automatically switched to ${CampusService.getCampusDisplayName(timetable.campus)} to match timetable');
          }
          
          // Always check for updated courses from Firestore
          await _loadCoursesFromFirestore(timetable);
          
          return timetable;
        }
        print('Timetable not found in Firestore, checking local storage...');
      }
      
      // Check local storage (for guests or as fallback)
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final key = 'timetable_$id';
      final data = prefs.getString(key);
      
      print('Looking for key: $key');
      if (data != null) {
        print('Found timetable data, parsing...');
        final jsonData = jsonDecode(data);
        final timetable = Timetable.fromJson(jsonData);
        print('Successfully parsed timetable: ${timetable.name}');
        
        // Set the campus to match the timetable's campus
        if (CampusService.currentCampus != timetable.campus) {
          await CampusService.setCampus(timetable.campus);
          print('Campus automatically switched to ${CampusService.getCampusDisplayName(timetable.campus)} to match timetable');
        }
        
        // Always check for updated courses from Firestore
        await _loadCoursesFromFirestore(timetable);
        
        return timetable;
      } else {
        print('No data found for key: $key');
        
        // Debug: List all keys to see what's actually stored
        final allKeys = prefs.getKeys();
        print('All stored keys: $allKeys');
      }
      
      return null;
    } catch (e) {
      print('Error getting timetable by id: $e');
      return null;
    }
  }

  Future<void> deleteTimetable(String id) async {
    try {
      if (_authService.isAuthenticated) {
        print('Deleting timetable from Firestore...');
        final success = await _firestoreService.deleteTimetableById(id);
        if (!success) {
          print('Failed to delete from Firestore, deleting from local storage...');
        }
      }
      
      // Also delete from local storage (for guests or as cleanup)
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
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
      print('Error deleting timetable: $e');
    }
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
      print('Attempting to migrate from old timetable format...');
      
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final oldData = prefs.getString(_storageKey);
      
      if (oldData != null) {
        print('Found old timetable data, migrating...');
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
          
          print('Migration completed successfully');
          return migratedTimetable;
        }
      }
      
      print('No old format timetable found');
      return null;
    } catch (e) {
      print('Error during migration: $e');
      return null;
    }
  }
}