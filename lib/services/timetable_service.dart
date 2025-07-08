import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import 'clash_detector.dart';
import 'xlsx_parser.dart';

class TimetableService {
  static const String _storageKey = 'user_timetable_data';
  
  // Save timetable using SharedPreferences
  Future<void> saveTimetable(Timetable timetable) async {
    try {
      print('Saving timetable to SharedPreferences...');
      
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
      
      print('Timetable saved successfully to SharedPreferences');
    } catch (e) {
      print('Error saving timetable: $e');
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

  // Load timetable using SharedPreferences
  Future<Timetable> loadTimetable() async {
    try {
      print('Loading timetable from SharedPreferences...');
      
      // Initialize SharedPreferences for web compatibility
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          print('Mock values already set or not needed: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      Timetable timetable;
      final data = prefs.getString(_storageKey);
      
      if (data == null) {
        print('No existing timetable found, creating new one');
        timetable = Timetable(
          availableCourses: [],
          selectedSections: [],
          clashWarnings: [],
        );
      } else {
        print('Found existing timetable data');
        final jsonData = jsonDecode(data);
        timetable = Timetable.fromJson(jsonData);
      }
      
      if (timetable.availableCourses.isEmpty) {
        await _loadCoursesFromXlsx(timetable);
      }
      
      return timetable;
    } catch (e) {
      print('Error loading timetable: $e');
      final timetable = Timetable(
        availableCourses: [],
        selectedSections: [],
        clashWarnings: [],
      );
      await _loadCoursesFromXlsx(timetable);
      return timetable;
    }
  }

  Future<void> _loadCoursesFromXlsx(Timetable timetable) async {
    try {
      print('Attempting to load courses from XLSX assets...');
      final ByteData data = await rootBundle.load('DRAFT TIMETABLE I SEM 2025 -26.xlsx');
      final Uint8List bytes = data.buffer.asUint8List();
      print('Loaded XLSX file from assets (${bytes.length} bytes)');
      
      final courses = await XlsxParser.parseXlsxBytes(bytes);
      print('Parsed ${courses.length} courses from XLSX');
      
      // Clear existing courses before adding new ones
      timetable.availableCourses.clear();
      timetable.availableCourses.addAll(courses);
      
      if (courses.isNotEmpty) {
        print('First course: ${courses.first.courseCode} - ${courses.first.courseTitle}');
      }
      
      await saveTimetable(timetable);
      print('Saved timetable with XLSX courses');
    } catch (e) {
      print('Error loading courses from XLSX: $e');
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