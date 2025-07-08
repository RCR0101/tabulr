import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'clash_detector.dart';
import 'xlsx_parser.dart';

class TimetableService {
  static const String _fileName = 'timetable_data.json';
  
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/$_fileName');
  }

  Future<void> saveTimetable(Timetable timetable) async {
    final file = await _localFile;
    await file.writeAsString(jsonEncode(timetable.toJson()));
  }

  Future<Timetable> loadTimetable() async {
    try {
      final file = await _localFile;
      Timetable timetable;
      
      if (!await file.exists()) {
        timetable = Timetable(
          availableCourses: [],
          selectedSections: [],
          clashWarnings: [],
        );
      } else {
        final contents = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(contents);
        timetable = Timetable.fromJson(json);
      }
      
      if (timetable.availableCourses.isEmpty) {
        await _loadCoursesFromXlsx(timetable);
      }
      
      return timetable;
    } catch (e) {
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
    final course = timetable.availableCourses.firstWhere(
      (c) => c.courseCode == courseCode,
      orElse: () => throw Exception('Course not found'),
    );

    final section = course.sections.firstWhere(
      (s) => s.sectionId == sectionId,
      orElse: () => throw Exception('Section not found'),
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

  List<TimetableSlot> generateTimetableSlots(List<SelectedSection> selectedSections) {
    List<TimetableSlot> slots = [];
    
    for (var selectedSection in selectedSections) {
      for (var day in selectedSection.section.days) {
        slots.add(TimetableSlot(
          day: day,
          hours: selectedSection.section.hours,
          courseCode: selectedSection.courseCode,
          sectionId: selectedSection.sectionId,
          instructor: selectedSection.section.instructor,
          room: selectedSection.section.room,
        ));
      }
    }
    
    return slots;
  }

}