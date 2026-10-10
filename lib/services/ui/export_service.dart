import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../constants/app_constants.dart';
import '../../models/course.dart';
import '../../models/export_options.dart';
import '../../models/timetable.dart';
import 'dart:convert';
import '../data/campus_service.dart';

// Platform-specific implementations
import 'export_service_stub.dart'
    if (dart.library.js_interop) 'export_service_web.dart'
    if (dart.library.io) 'export_service_io.dart';

class ExportService {
  /// Saves the timetable as an .ics file. Built by the `exportIcs` function,
  /// the same generator as the live calendar feed, so the file and the
  /// subscription agree on which days have class (holidays and "classwork
  /// suspended" days are left out).
  static Future<String> exportToICS(
    List<SelectedSection> selectedSections, {
    required String campusId,
    String? timetableId,
    String? calendarName,
    ExportOptions options = const ExportOptions(),
  }) async {
    final result = await FirebaseFunctions.instanceFor(
      region: FirebaseConfig.functionsRegion,
    ).httpsCallable('exportIcs').call({
      'selections': selectedSections.map((s) => s.toJson()).toList(),
      'campus': campusId,
      'timetableId': timetableId,
      'calendarName': calendarName,
      'options': {
        'showCourseCode': options.showCourseCode,
        'showCourseTitle': options.showCourseTitle,
        'showSectionId': options.showSectionId,
        'showInstructor': options.showInstructor,
        'showRoom': options.showRoom,
        'showExamDates': options.showExamDates,
      },
    });
    final ics = (result.data as Map)['ics'] as String;
    return await ExportServiceStub.saveIcsContent(ics);
  }

  static Future<String> exportToTTWithFilePicker(Timetable timetable) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final defaultFileName =
          '${timetable.name.replaceAll(RegExp(r'[^\w\s-]'), '')}_$timestamp.tt';

      final customPath = await pickSaveLocationForTT(defaultFileName);
      if (customPath == null) {
        throw Exception('Export cancelled by user');
      }

      return await exportToTT(timetable, customPath: customPath);
    } catch (e) {
      throw Exception('Failed to export .tt file: $e');
    }
  }

  static Future<String> exportToTT(
    Timetable timetable, {
    String? customPath,
  }) async {
    try {
      // Create .tt file format with metadata and timetable data
      final ttData = {
        'version': '1.0',
        'exportedAt': DateTime.now().toIso8601String(),
        'exportedBy': 'Tabulr',
        'timetable': {
          'id': timetable.id,
          'name': timetable.name,
          'createdAt': timetable.createdAt.toIso8601String(),
          'updatedAt': timetable.updatedAt.toIso8601String(),
          'campus': timetable.campus.toString().split('.').last,
          'selectedSections':
              timetable.selectedSections
                  .map(
                    (s) => {
                      'courseCode': s.courseCode,
                      'sectionId': s.sectionId,
                      'section': {
                        'sectionId': s.section.sectionId,
                        'type': s.section.type.toString().split('.').last,
                        'instructor': s.section.instructor,
                        'room': s.section.room,
                        'schedule':
                            s.section.schedule
                                .map(
                                  (entry) => {
                                    'days':
                                        entry.days
                                            .map(
                                              (d) =>
                                                  d.toString().split('.').last,
                                            )
                                            .toList(),
                                    'hours': entry.hours,
                                  },
                                )
                                .toList(),
                      },
                    },
                  )
                  .toList(),
          'courses':
              timetable.availableCourses
                  .map(
                    (c) => {
                      'courseCode': c.courseCode,
                      'courseTitle': c.courseTitle,
                      'lectureCredits': c.lectureCredits,
                      'practicalCredits': c.practicalCredits,
                      'totalCredits': c.totalCredits,
                      'midSemExam':
                          c.midSemExam != null
                              ? {
                                'date': c.midSemExam!.date.toIso8601String(),
                                'timeSlot':
                                    c.midSemExam!.timeSlot
                                        .toString()
                                        .split('.')
                                        .last,
                              }
                              : null,
                      'endSemExam':
                          c.endSemExam != null
                              ? {
                                'date': c.endSemExam!.date.toIso8601String(),
                                'timeSlot':
                                    c.endSemExam!.timeSlot
                                        .toString()
                                        .split('.')
                                        .last,
                              }
                              : null,
                    },
                  )
                  .toList(),
        },
      };

      // Convert to JSON string with pretty printing
      final jsonString = JsonEncoder.withIndent('  ').convert(ttData);

      // Use platform-specific implementation to save .tt file
      return await ExportServiceStub.saveTTContent(jsonString, customPath);
    } catch (e) {
      throw Exception('Failed to export .tt file: $e');
    }
  }

  static Future<String?> pickAndReadTTFile() async {
    return await ExportServiceStub.pickAndReadTTFile();
  }

  static Future<String?> pickSaveLocationForTT(String defaultFileName) async {
    return await ExportServiceStub.pickSaveLocationForTT(defaultFileName);
  }

  static Future<Timetable> importFromTTContent(String ttContent) async {
    try {
      // Parse JSON
      final ttData = jsonDecode(ttContent);

      // Validate file format
      if (ttData['version'] == null || ttData['timetable'] == null) {
        throw Exception('Invalid .tt file format');
      }

      final timetableData = ttData['timetable'];

      // Parse campus
      final campusString = timetableData['campus'] as String?;
      final Campus campus =
          campusString != null
              ? Campus.fromCode(campusString.toLowerCase())
              : Campus.hyderabad;

      // Parse courses
      final courses =
          (timetableData['courses'] as List).map((courseJson) {
            return Course(
              courseCode: courseJson['courseCode'],
              courseTitle: courseJson['courseTitle'],
              lectureCredits: courseJson['lectureCredits'],
              practicalCredits: courseJson['practicalCredits'],
              totalCredits: courseJson['totalCredits'],
              sections: [], // Will be populated from selected sections
              midSemExam:
                  courseJson['midSemExam'] != null
                      ? ExamSchedule(
                        date: DateTime.parse(courseJson['midSemExam']['date']),
                        timeSlot: TimeSlot.values.firstWhere(
                          (e) => e.toString().endsWith(
                            '.${courseJson['midSemExam']['timeSlot']}',
                          ),
                        ),
                      )
                      : null,
              endSemExam:
                  courseJson['endSemExam'] != null
                      ? ExamSchedule(
                        date: DateTime.parse(courseJson['endSemExam']['date']),
                        timeSlot: TimeSlot.values.firstWhere(
                          (e) => e.toString().endsWith(
                            '.${courseJson['endSemExam']['timeSlot']}',
                          ),
                        ),
                      )
                      : null,
            );
          }).toList();

      // Parse selected sections
      final selectedSections =
          (timetableData['selectedSections'] as List).map((sectionJson) {
            final sectionData = sectionJson['section'];
            final section = Section(
              sectionId: sectionData['sectionId'],
              type: SectionType.values.firstWhere(
                (e) => e.toString().endsWith('.${sectionData['type']}'),
              ),
              instructor: sectionData['instructor'],
              room: sectionData['room'],
              schedule:
                  (sectionData['schedule'] as List).map((scheduleJson) {
                    return ScheduleEntry(
                      days:
                          (scheduleJson['days'] as List)
                              .map(
                                (dayString) => DayOfWeek.values.firstWhere(
                                  (e) => e.toString().endsWith('.$dayString'),
                                ),
                              )
                              .toList(),
                      hours: List<int>.from(scheduleJson['hours']),
                    );
                  }).toList(),
            );

            return SelectedSection(
              courseCode: sectionJson['courseCode'],
              sectionId: sectionJson['sectionId'],
              section: section,
            );
          }).toList();

      // Create and return timetable with a new ID and updated timestamps
      // This ensures the imported timetable doesn't conflict with existing ones
      final now = DateTime.now();
      final originalName = timetableData['name'] ?? 'Imported Timetable';

      return Timetable(
        id:
            now.millisecondsSinceEpoch
                .toString(), // Always generate a new unique ID
        name: originalName,
        createdAt: now, // Set creation time to now
        updatedAt: now, // Set update time to now
        campus: campus,
        availableCourses: courses,
        selectedSections: selectedSections,
        clashWarnings: [], // Will be recalculated
      );
    } catch (e) {
      throw Exception('Failed to import .tt file: $e');
    }
  }

  static Future<Timetable> importFromTT(String filePath) async {
    try {
      // Read .tt file content
      final ttContent = await ExportServiceStub.readTTFile(filePath);
      return await importFromTTContent(ttContent);
    } catch (e) {
      throw Exception('Failed to import .tt file: $e');
    }
  }

  static Future<Timetable?> importFromTTWithFilePicker() async {
    try {
      final ttContent = await pickAndReadTTFile();
      if (ttContent == null) return null; // User cancelled
      return await importFromTTContent(ttContent);
    } catch (e) {
      throw Exception('Failed to import .tt file: $e');
    }
  }

  // Cap the exported image so its longest side stays within the WebGL
  // MAX_TEXTURE_SIZE that CanvasKit relies on. Many mobile/integrated GPUs
  // limit this to 4096px per side, so a full timetable at a fixed 3x pixel
  // ratio (~5000px+) makes toImage() fail on those devices while succeeding on
  // desktop GPUs (16384px). 4000 leaves a small safety margin.
  static const double _maxExportImageDimension = 4000.0;
  static const double _preferredExportPixelRatio = 3.0;

  static Future<String> exportToPNG(GlobalKey key, {String? customPath}) async {
    try {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final Size size = boundary.size;
      final double longestSide = math.max(size.width, size.height);
      double pixelRatio = _preferredExportPixelRatio;
      if (longestSide > 0 &&
          longestSide * pixelRatio > _maxExportImageDimension) {
        pixelRatio = (_maxExportImageDimension / longestSide).clamp(
          1.0,
          _preferredExportPixelRatio,
        );
      }

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Use platform-specific implementation
      return await ExportServiceStub.savePngBytes(pngBytes, customPath);
    } catch (e) {
      throw Exception('Failed to export PNG: $e');
    }
  }
}
