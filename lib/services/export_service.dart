import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:uuid/uuid.dart';
import '../models/course.dart';
import '../models/timetable.dart';

// Platform-specific implementations
import 'export_service_stub.dart'
    if (dart.library.html) 'export_service_web.dart'
    if (dart.library.io) 'export_service_io.dart';

/// Escape text per RFC 5545: commas, semicolons, backslashes, and newlines
String _escapeText(String input) {
  return input
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');
}

/// Fold lines longer than 75 bytes: insert CRLF + single space per RFC 5545
String _foldLine(String line) {
  final bytes = line.codeUnits;
  const maxOctets = 75;
  if (bytes.length <= maxOctets) return line;
  StringBuffer buf = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    int end = i + maxOctets;
    if (end >= bytes.length) {
      buf.write(String.fromCharCodes(bytes.sublist(i)));
      break;
    }
    // Find slice up to end
    buf.write(String.fromCharCodes(bytes.sublist(i, end)));
    buf.write('\r\n ');
    i = end;
  }
  return buf.toString();
}

/// Format a DateTime as UTC in the ICS format: YYYYMMDDTHHMMSSZ
String _formatUtcForICS(DateTime dt) {
  final utc = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String year = utc.year.toString().padLeft(4, '0');
  String month = two(utc.month);
  String day = two(utc.day);
  String hour = two(utc.hour);
  String minute = two(utc.minute);
  String second = two(utc.second);
  return '${year}${month}${day}T${hour}${minute}${second}Z';
}

class ExportService {
  static Future<String> exportToICS(List<SelectedSection> selectedSections, List<Course> courses) async {
    // Header
    final now = DateTime.now();
    final dtstamp = _formatUtcForICS(now);
    final uuid = Uuid();

    List<String> lines = [
      'BEGIN:VCALENDAR',
      'PRODID:-//Tabulr//EN',
      'VERSION:2.0',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
    ];

    for (var selectedSection in selectedSections) {
      final course = courses.firstWhere((c) => c.courseCode == selectedSection.courseCode);

      // Regular class events
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          for (var hour in scheduleEntry.hours) {
            final startTime = _getDateTime(day, hour);
            final endTime = _getDateTime(day, hour, endTime: true);

            String uid = '${selectedSection.courseCode}-${selectedSection.sectionId}-$day-$hour-${uuid.v4()}@tabulr.app';
            String summary = _escapeText('${selectedSection.courseCode} - ${selectedSection.sectionId}');
            String description = _escapeText(
                'Course: ${course.courseTitle}\nInstructor: ${selectedSection.section.instructor}\nRoom: ${selectedSection.section.room}');
            String location = _escapeText(selectedSection.section.room);
            String rruleDay = _getDayAbbreviation(day);
            String dtStartStr = _formatUtcForICS(startTime);
            String dtEndStr = _formatUtcForICS(endTime);

            List<String> eventLines = [
              'BEGIN:VEVENT',
              'UID:$uid',
              'DTSTAMP:$dtstamp',
              'DTSTART:$dtStartStr',
              'DTEND:$dtEndStr',
              'SUMMARY:$summary',
              'DESCRIPTION:$description',
              'LOCATION:$location',
              'RRULE:FREQ=WEEKLY;UNTIL=20250531T235959Z;BYDAY=$rruleDay',
              'END:VEVENT'
            ];

            // Add each line (folding can be done later if needed)
            lines.addAll(eventLines);
          }
        }
      }

      // MidSem exam
      if (course.midSemExam != null) {
        final startTime = _getExamDateTime(course.midSemExam!);
        final endTime = _getExamDateTime(course.midSemExam!, endTime: true);

        String uid = '${selectedSection.courseCode}-midsem-${uuid.v4()}@tabulr.app';
        String summary = _escapeText('${selectedSection.courseCode} MidSem Exam');
        String description = _escapeText('MidSem Examination for ${course.courseTitle}');
        String dtStartStr = _formatUtcForICS(startTime);
        String dtEndStr = _formatUtcForICS(endTime);

        List<String> eventLines = [
          'BEGIN:VEVENT',
          'UID:$uid',
          'DTSTAMP:$dtstamp',
          'DTSTART:$dtStartStr',
          'DTEND:$dtEndStr',
          'SUMMARY:$summary',
          'DESCRIPTION:$description',
          'END:VEVENT'
        ];
        lines.addAll(eventLines);
      }

      // EndSem exam
      if (course.endSemExam != null) {
        final startTime = _getExamDateTime(course.endSemExam!);
        final endTime = _getExamDateTime(course.endSemExam!, endTime: true);

        String uid = '${selectedSection.courseCode}-endsem-${uuid.v4()}@tabulr.app';
        String summary = _escapeText('${selectedSection.courseCode} EndSem Exam');
        String description = _escapeText('EndSem Examination for ${course.courseTitle}');
        String dtStartStr = _formatUtcForICS(startTime);
        String dtEndStr = _formatUtcForICS(endTime);

        List<String> eventLines = [
          'BEGIN:VEVENT',
          'UID:$uid',
          'DTSTAMP:$dtstamp',
          'DTSTART:$dtStartStr',
          'DTEND:$dtEndStr',
          'SUMMARY:$summary',
          'DESCRIPTION:$description',
          'END:VEVENT'
        ];
        lines.addAll(eventLines);
      }
    }

    lines.add('END:VCALENDAR');

    // Join with CRLF line endings
    final icsContent = lines.join('\r\n') + '\r\n';

    return await ExportServiceStub.saveIcsContent(icsContent);
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
      
      // Use platform-specific implementation
      return await ExportServiceStub.savePngBytes(pngBytes, customPath);
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
    
    // Map hour to actual time based on TimeSlotInfo.hourSlotNames
    final hourToTime = {
      1: [8, 0],   // 8:00-8:50 AM
      2: [9, 0],   // 9:00-9:50 AM
      3: [10, 0],  // 10:00-10:50 AM
      4: [11, 0],  // 11:00-11:50 AM
      5: [12, 0],  // 12:00-12:50 PM
      6: [13, 0],  // 1:00-1:50 PM
      7: [14, 0],  // 2:00-2:50 PM
      8: [15, 0],  // 3:00-3:50 PM
      9: [16, 0],  // 4:00-4:50 PM
      10: [17, 0], // 5:00-5:50 PM
      11: [18, 0], // 6:00-6:50 PM
      12: [19, 0], // 7:00-7:50 PM
    };
    
    final timeSlot = hourToTime[hour];
    if (timeSlot == null) {
      throw Exception('Invalid hour: $hour');
    }
    
    final dayOffsetValue = dayOffset[day];
    if (dayOffsetValue == null) {
      throw Exception('Invalid day: $day');
    }
    
    final targetDate = monday.add(Duration(days: dayOffsetValue));
    final startHour = timeSlot[0];
    final startMinute = timeSlot[1];
    
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      startHour,
      endTime ? startMinute + 50 : startMinute, // Each class is 50 minutes
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

  static String _getDayAbbreviation(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.M: return 'MO';
      case DayOfWeek.T: return 'TU';
      case DayOfWeek.W: return 'WE';
      case DayOfWeek.Th: return 'TH';
      case DayOfWeek.F: return 'FR';
      case DayOfWeek.S: return 'SA';
    }
  }
}