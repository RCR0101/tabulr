import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/course.dart';
import '../models/timetable.dart';

// Web-specific imports
import 'dart:html' as html;
import 'dart:convert';

class ExportService {
  static Future<String> exportToICS(List<SelectedSection> selectedSections, List<Course> courses) async {
    // Create manual ICS content since the library API is complex
    String icsContent = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Tabulr//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
''';

    for (var selectedSection in selectedSections) {
      final course = courses.firstWhere((c) => c.courseCode == selectedSection.courseCode);
      
      // Add regular class events using new schedule structure
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          for (var hour in scheduleEntry.hours) {
            final startTime = _getDateTime(day, hour);
            final endTime = _getDateTime(day, hour, endTime: true);
            
            icsContent += '''BEGIN:VEVENT
UID:${selectedSection.courseCode}-${selectedSection.sectionId}-$day-$hour
DTSTART:${_formatDateTimeForICS(startTime)}
DTEND:${_formatDateTimeForICS(endTime)}
SUMMARY:${selectedSection.courseCode} - ${selectedSection.sectionId}
DESCRIPTION:Course: ${course.courseTitle}\\nInstructor: ${selectedSection.section.instructor}\\nRoom: ${selectedSection.section.room}
LOCATION:${selectedSection.section.room}
RRULE:FREQ=WEEKLY;UNTIL=20250531T235959Z
END:VEVENT
''';
          }
        }
      }
      
      // Add exam events
      if (course.midSemExam != null) {
        final startTime = _getExamDateTime(course.midSemExam!);
        final endTime = _getExamDateTime(course.midSemExam!, endTime: true);
        
        icsContent += '''BEGIN:VEVENT
UID:${selectedSection.courseCode}-midsem
DTSTART:${_formatDateTimeForICS(startTime)}
DTEND:${_formatDateTimeForICS(endTime)}
SUMMARY:${selectedSection.courseCode} MidSem Exam
DESCRIPTION:MidSem Examination for ${course.courseTitle}
END:VEVENT
''';
      }
      
      if (course.endSemExam != null) {
        final startTime = _getExamDateTime(course.endSemExam!);
        final endTime = _getExamDateTime(course.endSemExam!, endTime: true);
        
        icsContent += '''BEGIN:VEVENT
UID:${selectedSection.courseCode}-endsem
DTSTART:${_formatDateTimeForICS(startTime)}
DTEND:${_formatDateTimeForICS(endTime)}
SUMMARY:${selectedSection.courseCode} EndSem Exam
DESCRIPTION:EndSem Examination for ${course.courseTitle}
END:VEVENT
''';
      }
    }
    
    icsContent += 'END:VCALENDAR\n';
    
    if (kIsWeb) {
      // For web, trigger download
      final blob = html.Blob([icsContent], 'text/calendar');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = 'timetable.ics';
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
      return 'timetable.ics';
    } else {
      // For mobile/desktop, save to documents
      throw UnsupportedError('File saving not implemented for this platform');
    }
  }

  static String _formatDateTimeForICS(DateTime dateTime) {
    return dateTime.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').replaceAll('.000Z', 'Z');
  }

  static Future<String> exportToPNG(GlobalKey key, {String? customPath}) async {
    try {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }
      
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      
      if (kIsWeb) {
        // For web, trigger download
        final blob = html.Blob([pngBytes], 'image/png');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = customPath ?? 'timetable.png';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        return customPath ?? 'timetable.png';
      } else {
        // For mobile/desktop, save to documents
        throw UnsupportedError('File saving not implemented for this platform');
      }
    } catch (e) {
      throw Exception('Failed to export PNG: $e');
    }
  }

  static DateTime _getDateTime(DayOfWeek day, int hour, {bool endTime = false}) {
    // Get the Monday of the current week (assuming semester starts on a Monday)
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    
    // Map day of week to offset from Monday
    final dayOffset = {
      DayOfWeek.M: 0,
      DayOfWeek.T: 1,
      DayOfWeek.W: 2,
      DayOfWeek.Th: 3,
      DayOfWeek.F: 4,
      DayOfWeek.S: 5,
    };
    
    // Map hour to actual time (hour 1 = 8:00 AM)
    final startHour = 7 + hour; // hour 1 = 8:00 AM
    final endHour = endTime ? startHour + 1 : startHour;
    
    final targetDate = monday.add(Duration(days: dayOffset[day]!));
    
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      endTime ? endHour : startHour,
      0,
    );
  }

  static DateTime _getExamDateTime(ExamSchedule exam, {bool endTime = false}) {
    final baseTime = exam.timeSlot == TimeSlot.FN 
        ? DateTime(exam.date.year, exam.date.month, exam.date.day, 9, 30)
        : DateTime(exam.date.year, exam.date.month, exam.date.day, 14, 0);
    
    if (endTime) {
      return baseTime.add(const Duration(hours: 3));
    }
    
    return baseTime;
  }
}