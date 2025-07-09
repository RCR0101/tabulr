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

class TimetableService {
  static const String _storageKey = 'user_timetable_data';
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final CourseDataService _courseDataService = CourseDataService();
  
  // Save timetable using Firestore for authenticated users or local storage for guests
  Future<void> saveTimetable(Timetable timetable) async {
    try {
      // If user is authenticated, save to Firestore
      if (_authService.isAuthenticated) {
        print('Saving timetable to Firestore...');
        final success = await _firestoreService.saveTimetable(timetable);
        if (success) {
          print('Timetable saved successfully to Firestore');
        } else {
          print('Failed to save to Firestore, falling back to local storage');
          await _saveToLocalStorage(timetable);
        }
      } else {
        // Guest user - save to local storage
        print('Guest user - saving timetable to local storage...');
        await _saveToLocalStorage(timetable);
      }
    } catch (e) {
      print('Error saving timetable: $e');
      // Fallback to local storage
      await _saveToLocalStorage(timetable);
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
        timetable = Timetable(
          availableCourses: [],
          selectedSections: [],
          clashWarnings: [],
        );
      }
      
      // Load courses from Firestore if not already loaded
      if (timetable.availableCourses.isEmpty) {
        await _loadCoursesFromFirestore(timetable);
      }
      
      return timetable;
    } catch (e) {
      print('Error loading timetable: $e');
      final timetable = Timetable(
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
}