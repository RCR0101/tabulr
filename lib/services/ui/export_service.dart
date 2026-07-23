import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../constants/app_constants.dart';
import '../../models/academic_calendar_event.dart';
import '../../models/course.dart';
import '../../models/export_options.dart';
import '../../models/timetable.dart';
import 'dart:convert';
import '../data/academic_calendar_service.dart';
import '../data/campus_service.dart';
import '../data/config_service.dart';

// Platform-specific implementations
import 'export_service_stub.dart'
    if (dart.library.html) 'export_service_web.dart'
    if (dart.library.io) 'export_service_io.dart';

final Map<int, List<int>> _hourToTime = ScheduleConstants.hourToTime;

/// Escape text per RFC 5545: commas, semicolons, backslashes, and newlines
String _escapeText(String input) {
  return input
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');
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
  return '$year$month${day}T$hour$minute${second}Z';
}

/// Format a DateTime's wall-clock fields directly (no UTC conversion), for use
/// with an explicit `TZID`. The exported time then means the same Asia/Kolkata
/// wall time on any device, rather than depending on the exporting device's own
/// timezone (which is what the old `...Z` UTC output silently assumed).
String _fmtLocalForICS(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final year = dt.year.toString().padLeft(4, '0');
  return '$year${two(dt.month)}${two(dt.day)}T'
      '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
}

/// Date-only `YYYYMMDD`, for all-day (`VALUE=DATE`) academic-calendar events.
String _fmtDateForICS(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}${two(dt.month)}${two(dt.day)}';
}

/// Treat [istWall]'s fields as Asia/Kolkata (+05:30) wall time and return the
/// matching UTC instant as an ICS string. Used for `RRULE` `UNTIL`, which must
/// be UTC when `DTSTART` carries a `TZID`.
String _istWallToUtcICS(DateTime istWall) {
  final utc = DateTime.utc(istWall.year, istWall.month, istWall.day,
          istWall.hour, istWall.minute, istWall.second)
      .subtract(const Duration(hours: 5, minutes: 30));
  return _formatUtcForICS(utc);
}

/// Group hour indices into runs of consecutive slots, so a two-hour class is one
/// calendar block instead of two adjacent 50-minute events.
List<List<int>> _consecutiveRuns(List<int> hours) {
  final sorted = [...hours]..sort();
  final runs = <List<int>>[];
  for (final h in sorted) {
    if (runs.isNotEmpty && h == runs.last.last + 1) {
      runs.last.add(h);
    } else {
      runs.add([h]);
    }
  }
  return runs;
}

String _sectionTypeLabel(SectionType type) => switch (type) {
      SectionType.L => 'Lecture',
      SectionType.P => 'Practical',
      SectionType.T => 'Tutorial',
    };

/// Fold a content line to the 75-octet limit (RFC 5545): continuation lines
/// begin with a single space. Counted on characters — exact for the ASCII
/// course data, and any over-length multibyte line still parses in practice.
String _foldICSLine(String line) {
  if (line.length <= 75) return line;
  final buf = StringBuffer(line.substring(0, 75));
  var i = 75;
  while (i < line.length) {
    final end = (i + 74 < line.length) ? i + 74 : line.length;
    buf.write('\r\n ');
    buf.write(line.substring(i, end));
    i = end;
  }
  return buf.toString();
}

/// India observes no DST, so Asia/Kolkata is a single fixed +05:30 offset.
const List<String> _vtimezoneLines = [
  'BEGIN:VTIMEZONE',
  'TZID:Asia/Kolkata',
  'BEGIN:STANDARD',
  'DTSTART:19700101T000000',
  'TZOFFSETFROM:+0530',
  'TZOFFSETTO:+0530',
  'TZNAME:IST',
  'END:STANDARD',
  'END:VTIMEZONE',
];

/// `EXDATE` line (with `TZID`) for the holiday breaks that fall on [day] at the
/// class's [startHour]. The times must match the recurrence's local start
/// exactly, so they use the same wall-clock/TZID form as `DTSTART`.
String _generateExDates(DayOfWeek day, int startHour) {
  final breakPeriods = ConfigService().breakPeriods;

  // Map day of week to DateTime.weekday (1=Monday..7=Sunday)
  final dayOffsetMap = {
    DayOfWeek.M: 1,
    DayOfWeek.T: 2,
    DayOfWeek.W: 3,
    DayOfWeek.Th: 4,
    DayOfWeek.F: 5,
    DayOfWeek.S: 6,
  };

  final targetWeekday = dayOffsetMap[day];
  final timeSlot = _hourToTime[startHour];
  if (targetWeekday == null || timeSlot == null) return '';

  final exDates = <String>[];
  for (final period in breakPeriods) {
    DateTime current = period['start'] as DateTime;
    final end = (period['end'] as DateTime).add(const Duration(days: 1));
    while (current.isBefore(end)) {
      if (current.weekday == targetWeekday) {
        exDates.add(_fmtLocalForICS(DateTime(current.year, current.month,
            current.day, timeSlot[0], timeSlot[1])));
      }
      current = current.add(const Duration(days: 1));
    }
  }

  if (exDates.isEmpty) return '';
  return 'EXDATE;TZID=Asia/Kolkata:${exDates.join(',')}';
}

class ExportService {
  static Future<String> exportToICS(
    List<SelectedSection> selectedSections,
    List<Course> courses, {
    String? timetableId,
    String? calendarName,
    String? campusId,
    ExportOptions options = const ExportOptions(),
  }) async {
    // Best-effort: fold the campus's academic calendar (add/drop deadlines,
    // exam windows) into the export as reminders. A failure here must not stop
    // the user exporting their timetable.
    var academicEvents = const <AcademicCalendarEvent>[];
    if (campusId != null) {
      try {
        academicEvents = await AcademicCalendarService().load(campusId: campusId);
      } catch (_) {
        academicEvents = const [];
      }
    }
    final icsContent = buildIcsContent(
      selectedSections,
      courses,
      timetableId: timetableId,
      calendarName: calendarName,
      academicEvents: academicEvents,
      options: options,
    );
    return await ExportServiceStub.saveIcsContent(icsContent);
  }

  /// Builds the raw iCalendar document. Separated from the file-save step so the
  /// output can be asserted on directly in tests.
  @visibleForTesting
  static String buildIcsContent(
    List<SelectedSection> selectedSections,
    List<Course> courses, {
    String? timetableId,
    String? calendarName,
    List<AcademicCalendarEvent> academicEvents = const [],
    ExportOptions options = const ExportOptions(),
  }) {
    final dtstamp = _formatUtcForICS(DateTime.now());
    // Stable per-timetable namespace, so re-importing after an edit updates the
    // same events instead of piling up duplicates (the old random-UUID UIDs
    // created a fresh copy every export).
    final ns = (timetableId == null || timetableId.isEmpty)
        ? 'tt'
        : timetableId.replaceAll(RegExp(r'\s'), '');
    final calName = _escapeText(
      'Tabulr${(calendarName != null && calendarName.isNotEmpty) ? ' — $calendarName' : ''}',
    );

    // DTSTART carries a TZID, so UNTIL must be UTC. Bound the recurrence at the
    // end of the last semester day.
    final semEnd = ConfigService().semesterEnd;
    final until = _istWallToUtcICS(
        DateTime(semEnd.year, semEnd.month, semEnd.day, 23, 59, 59));

    String uid(String suffix) =>
        'tabulr-$ns-$suffix@tabulr.app'.replaceAll(RegExp(r'\s'), '');

    // The export-options dialog (shared with the PNG export) lets the user pick
    // which fields ride along. A SUMMARY can never be empty, so it falls back to
    // the course code when both name fields are switched off.
    String summaryFor(String code, String title) {
      final parts = <String>[];
      if (options.showCourseCode) parts.add(code);
      if (options.showCourseTitle && title.isNotEmpty) parts.add(title);
      return parts.isEmpty ? code : parts.join(' — ');
    }

    final lines = <String>[
      'BEGIN:VCALENDAR',
      'PRODID:-//Tabulr//EN',
      'VERSION:2.0',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:$calName',
      'X-WR-TIMEZONE:Asia/Kolkata',
      ..._vtimezoneLines,
    ];

    // Regular class events — one per (section, day, run of consecutive hours).
    for (final sel in selectedSections) {
      final course = courses.firstWhere((c) => c.courseCode == sel.courseCode);
      final typeLabel = _sectionTypeLabel(sel.section.type);

      for (final entry in sel.section.schedule) {
        final runs = _consecutiveRuns(entry.hours);
        for (final day in entry.days) {
          for (final run in runs) {
            final start = _getDateTime(day, run.first);
            final end = _getDateTime(day, run.last, endTime: true);
            final exdate = _generateExDates(day, run.first);

            final descLines = <String>[
              if (options.showSectionId) '$typeLabel · Section ${sel.sectionId}',
              if (options.showInstructor) 'Instructor: ${sel.section.instructor}',
              if (options.showRoom) 'Room: ${sel.section.room}',
            ];

            lines.addAll([
              'BEGIN:VEVENT',
              'UID:${uid('${sel.courseCode}-${sel.sectionId}-${day.name}-${run.first}')}',
              'DTSTAMP:$dtstamp',
              'DTSTART;TZID=Asia/Kolkata:${_fmtLocalForICS(start)}',
              'DTEND;TZID=Asia/Kolkata:${_fmtLocalForICS(end)}',
              'SUMMARY:${_escapeText(summaryFor(sel.courseCode, course.courseTitle))}',
              if (descLines.isNotEmpty)
                'DESCRIPTION:${_escapeText(descLines.join('\n'))}',
              if (options.showRoom) 'LOCATION:${_escapeText(sel.section.room)}',
              'RRULE:FREQ=WEEKLY;UNTIL=$until;BYDAY=${_getDayAbbreviation(day)}',
              if (exdate.isNotEmpty) exdate,
              'BEGIN:VALARM',
              'ACTION:DISPLAY',
              'DESCRIPTION:${_escapeText('${sel.courseCode} starts in 10 minutes')}',
              'TRIGGER:-PT10M',
              'END:VALARM',
              'END:VEVENT',
            ]);
          }
        }
      }
    }

    // Exam events — once per course, unless the user opted them out. The
    // seat/room is only published mid-semester, so it is intentionally not
    // embedded here (that arrives via the live calendar feed later); the
    // description sets that expectation.
    final processed = <String>{};
    for (final sel in selectedSections) {
      if (!options.showExamDates) break;
      if (!processed.add(sel.courseCode)) continue;
      final course = courses.firstWhere((c) => c.courseCode == sel.courseCode);

      void addExam(ExamSchedule exam, String kind, String tag) {
        final start = _getExamDateTime(exam);
        final end = _getExamDateTime(exam, endTime: true);
        final examDesc = [
          if (options.showCourseTitle && course.courseTitle.isNotEmpty)
            course.courseTitle,
          'Seat/room is announced mid-semester.',
        ].join('\n');
        lines.addAll([
          'BEGIN:VEVENT',
          'UID:${uid('${sel.courseCode}-$tag')}',
          'DTSTAMP:$dtstamp',
          'DTSTART;TZID=Asia/Kolkata:${_fmtLocalForICS(start)}',
          'DTEND;TZID=Asia/Kolkata:${_fmtLocalForICS(end)}',
          'SUMMARY:${_escapeText(options.showCourseCode ? '${sel.courseCode} — $kind' : kind)}',
          'DESCRIPTION:${_escapeText(examDesc)}',
          // Exams matter more: a day-before heads-up and a 90-minute reminder.
          'BEGIN:VALARM',
          'ACTION:DISPLAY',
          'DESCRIPTION:${_escapeText('$kind tomorrow — ${sel.courseCode}')}',
          'TRIGGER:-P1D',
          'END:VALARM',
          'BEGIN:VALARM',
          'ACTION:DISPLAY',
          'DESCRIPTION:${_escapeText('$kind in 90 minutes — ${sel.courseCode}')}',
          'TRIGGER:-PT1H30M',
          'END:VALARM',
          'END:VEVENT',
        ]);
      }

      if (course.midSemExam != null) {
        addExam(course.midSemExam!, 'Mid-Sem Exam', 'midsem');
      }
      if (course.endSemExam != null) {
        addExam(course.endSemExam!, 'Comprehensive Exam', 'endsem');
      }
    }

    // Academic-calendar reminders — the actionable dates (add/drop, registration
    // deadlines and exam windows) as all-day events with a lead-time alarm.
    // Holidays and generic markers stay in the in-app calendar overlay, out of
    // the student's personal calendar.
    var calSeq = 0;
    for (final ev in academicEvents) {
      if (!ev.category.isReminderWorthy || ev.label.isEmpty) continue;
      final endExclusive = (ev.endDate ?? ev.date).add(const Duration(days: 1));
      final isDeadline = ev.category == AcademicEventCategory.deadline;
      final trigger = isDeadline ? '-P3D' : '-P1D';
      final leadLabel = isDeadline ? 'in 3 days' : 'tomorrow';
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${uid('cal-${_fmtDateForICS(ev.date)}-${calSeq++}')}',
        'DTSTAMP:$dtstamp',
        'DTSTART;VALUE=DATE:${_fmtDateForICS(ev.date)}',
        'DTEND;VALUE=DATE:${_fmtDateForICS(endExclusive)}',
        'SUMMARY:${_escapeText(ev.label)}',
        'DESCRIPTION:${_escapeText('BITS academic calendar')}',
        'TRANSP:TRANSPARENT',
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_escapeText('${ev.label} — $leadLabel')}',
        'TRIGGER:$trigger',
        'END:VALARM',
        'END:VEVENT',
      ]);
    }

    lines.add('END:VCALENDAR');

    return '${lines.map(_foldICSLine).join('\r\n')}\r\n';
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
      Campus campus = Campus.hyderabad;
      final campusString = timetableData['campus'] as String?;
      if (campusString != null) {
        switch (campusString.toLowerCase()) {
          case 'pilani':
            campus = Campus.pilani;
            break;
          case 'hyderabad':
            campus = Campus.hyderabad;
            break;
          case 'goa':
            campus = Campus.goa;
            break;
        }
      }

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
        pixelRatio = (_maxExportImageDimension / longestSide)
            .clamp(1.0, _preferredExportPixelRatio);
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

  static DateTime _getDateTime(
    DayOfWeek day,
    int hour, {
    bool endTime = false,
  }) {
    final monday = ConfigService().semesterStart;

    // Map day of week to offset from Monday
    final dayOffset = {
      DayOfWeek.M: 0,
      DayOfWeek.T: 1,
      DayOfWeek.W: 2,
      DayOfWeek.Th: 3,
      DayOfWeek.F: 4,
      DayOfWeek.S: 5,
    };

    final timeSlot = _hourToTime[hour];
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
    // Use campus-specific time slot mappings
    final slotTimes = TimeSlotInfo.getCampusExamTimes(CampusService.currentCampusCode);

    final timeInfo = slotTimes[exam.timeSlot];
    if (timeInfo == null) {
      throw Exception('Unknown time slot: ${exam.timeSlot}');
    }

    final baseTime = DateTime(
      exam.date.year,
      exam.date.month,
      exam.date.day,
      timeInfo[0],
      timeInfo[1],
    );

    if (endTime) {
      final duration =
          exam.timeSlot.toString().startsWith('TimeSlot.MS')
              ? ScheduleConstants.midsemExamDuration
              : ScheduleConstants.endsemExamDuration;
      return baseTime.add(duration);
    }

    return baseTime;
  }

  static String _getDayAbbreviation(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.M:
        return 'MO';
      case DayOfWeek.T:
        return 'TU';
      case DayOfWeek.W:
        return 'WE';
      case DayOfWeek.Th:
        return 'TH';
      case DayOfWeek.F:
        return 'FR';
      case DayOfWeek.S:
        return 'SA';
    }
  }
}
