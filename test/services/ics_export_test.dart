import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/export_options.dart';
import 'package:timetable_maker/services/ui/export_service.dart';

import '../helpers/test_data.dart';

/// Pulls the unfolded VEVENT blocks out of an ICS document for assertions.
List<String> _vevents(String ics) {
  // Unfold first (continuation lines start with a space).
  final unfolded = ics.replaceAll('\r\n ', '');
  final blocks = <String>[];
  final lines = unfolded.split('\r\n');
  StringBuffer? current;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      current = StringBuffer();
    } else if (line == 'END:VEVENT') {
      blocks.add(current.toString());
      current = null;
    } else {
      current?.writeln(line);
    }
  }
  return blocks;
}

void main() {
  group('buildIcsContent', () {
    test('emits a well-formed calendar with an Asia/Kolkata VTIMEZONE', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(sectionId: 'L1')],
        [makeCourse()],
        timetableId: 'abc',
        calendarName: 'My Sem',
      );

      expect(ics, startsWith('BEGIN:VCALENDAR'));
      expect(ics.trimRight(), endsWith('END:VCALENDAR'));
      expect(ics, contains('BEGIN:VTIMEZONE'));
      expect(ics, contains('TZID:Asia/Kolkata'));
      expect(ics, contains('X-WR-CALNAME:Tabulr — My Sem'));
      // Local time with TZID, never a UTC 'Z' stamp on DTSTART.
      expect(ics, contains('DTSTART;TZID=Asia/Kolkata:'));
      expect(ics, isNot(contains(RegExp(r'DTSTART:\d{8}T\d{6}Z'))));
    });

    test('class events carry a 10-minute VALARM', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [makeCourse()],
      );
      final events = _vevents(ics);
      expect(events, isNotEmpty);
      expect(events.first, contains('BEGIN:VALARM'));
      expect(events.first, contains('TRIGGER:-PT10M'));
    });

    test('merges consecutive hours into one block instead of two events', () {
      // A single day, two consecutive hours (8:00 and 9:00 slots).
      final section = makeSection(
        sectionId: 'L1',
        days: [DayOfWeek.M],
        hours: [1, 2],
      );
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(sectionId: 'L1', section: section)],
        [makeCourse(sections: [section])],
      );
      final events = _vevents(ics);
      expect(events, hasLength(1));
      // 8:00 → 9:50 (start of last hour + 50 min).
      expect(events.first, contains('DTSTART;TZID=Asia/Kolkata:'));
      expect(events.first, contains(RegExp(r'DTSTART;TZID=Asia/Kolkata:\d{8}T080000')));
      expect(events.first, contains(RegExp(r'DTEND;TZID=Asia/Kolkata:\d{8}T095000')));
    });

    test('UIDs are stable across exports (deterministic, not random)', () {
      final sections = [makeSelectedSection(sectionId: 'L1')];
      final courses = [makeCourse()];
      String uidOf(String ics) => _vevents(ics)
          .first
          .split('\n')
          .firstWhere((l) => l.startsWith('UID:'));

      final a = ExportService.buildIcsContent(sections, courses, timetableId: 'tt7');
      final b = ExportService.buildIcsContent(sections, courses, timetableId: 'tt7');
      expect(uidOf(a), equals(uidOf(b)));
      expect(uidOf(a), contains('tabulr-tt7-'));
    });

    test('exam events get two alarms and no embedded room', () {
      final course = makeCourse(
        midSemExam: makeExam(date: DateTime(2026, 3, 10)),
      );
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [course],
      );
      final examEvent = _vevents(ics)
          .firstWhere((e) => e.contains('Mid-Sem Exam'));
      expect(examEvent, contains('TRIGGER:-P1D'));
      expect(examEvent, contains('TRIGGER:-PT1H30M'));
      expect(examEvent, contains('announced mid-semester'));
      // Seat/room is intentionally deferred to the live feed.
      expect(examEvent, isNot(contains('LOCATION:')));
    });

    test('exam times use the timetable\'s own campus, not the global one', () {
      final course = makeCourse(midSemExam: makeExam(
        date: DateTime(2026, 3, 10),
        timeSlot: TimeSlot.FN,
      ));
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [course],
        campusId: 'pilani',
      );
      final examEvent = _vevents(ics)
          .firstWhere((e) => e.contains('Mid-Sem Exam'));
      expect(examEvent, contains(RegExp(r'DTSTART;TZID=Asia/Kolkata:\d{8}T080000')));
    });

    test('academic deadlines export as all-day reminders; holidays are omitted',
        () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [makeCourse()],
        academicEvents: [
          AcademicCalendarEvent(
            date: DateTime(2026, 3, 20),
            label: 'Last day for withdrawal from courses',
            category: AcademicEventCategory.deadline,
          ),
          AcademicCalendarEvent(
            date: DateTime(2026, 1, 26),
            label: 'Republic Day (H)',
            category: AcademicEventCategory.holiday,
          ),
        ],
      );
      final deadline = _vevents(ics)
          .firstWhere((e) => e.contains('Last day for withdrawal'));
      // All-day VALUE=DATE with an end date the following day (exclusive).
      expect(deadline, contains('DTSTART;VALUE=DATE:20260320'));
      expect(deadline, contains('DTEND;VALUE=DATE:20260321'));
      // Deadlines get a 3-day lead reminder.
      expect(deadline, contains('TRIGGER:-P3D'));
      // Holidays stay out of the personal calendar.
      expect(_vevents(ics).any((e) => e.contains('Republic Day')), isFalse);
    });

    test('a multi-day exam window spans to the inclusive end date', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [makeCourse()],
        academicEvents: [
          AcademicCalendarEvent(
            date: DateTime(2026, 5, 2),
            endDate: DateTime(2026, 5, 16),
            label: 'Comprehensive Examination',
            category: AcademicEventCategory.exam,
          ),
        ],
      );
      final exam = _vevents(ics)
          .firstWhere((e) => e.contains('Comprehensive Examination'));
      expect(exam, contains('DTSTART;VALUE=DATE:20260502'));
      // End is exclusive → the day after the inclusive 16th.
      expect(exam, contains('DTEND;VALUE=DATE:20260517'));
      expect(exam, contains('TRIGGER:-P1D'));
    });

    test('export options control which fields appear', () {
      final course = makeCourse(
        courseCode: 'CS F111',
        courseTitle: 'Intro to Programming',
        midSemExam: makeExam(date: DateTime(2026, 3, 10)),
      );
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(courseCode: 'CS F111', sectionId: 'L1')],
        [course],
        options: const ExportOptions(
          showCourseTitle: false,
          showInstructor: false,
          showRoom: false,
          showExamDates: false,
        ),
      );
      final events = _vevents(ics);
      final classEvent = events.first;
      // Title, instructor and room are all suppressed.
      expect(classEvent, contains('SUMMARY:CS F111'));
      expect(classEvent, isNot(contains('Intro to Programming')));
      expect(classEvent, isNot(contains('Instructor:')));
      expect(classEvent, isNot(contains('LOCATION:')));
      // Exams opted out entirely.
      expect(events.any((e) => e.contains('Mid-Sem Exam')), isFalse);
    });

    test('SUMMARY never goes empty even with both name fields off', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(courseCode: 'CS F111')],
        [makeCourse(courseCode: 'CS F111')],
        options: const ExportOptions(
          showCourseCode: false,
          showCourseTitle: false,
        ),
      );
      // Falls back to the course code rather than emitting a blank SUMMARY.
      expect(_vevents(ics).first, contains('SUMMARY:CS F111'));
    });

    test('long lines are folded to the 75-octet limit', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection()],
        [makeCourse(courseTitle: 'A' * 120)],
      );
      for (final line in ics.split('\r\n')) {
        // Folded continuation lines begin with a space; no raw line exceeds 75.
        expect(line.length, lessThanOrEqualTo(75),
            reason: 'unfolded line too long: $line');
      }
    });
  });
}
