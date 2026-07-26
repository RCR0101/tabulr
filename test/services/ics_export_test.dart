import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/export_options.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/ui/export_service.dart';

import '../helpers/test_data.dart';
import '../helpers/test_reporter.dart';

/// Pulls the unfolded VEVENT blocks out of an ICS document for assertions.
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

  // ── Property / metamorphic stress ────────────────────────────────────
  //
  // The cases above pin specific inputs to specific outputs. These fuzz
  // hundreds of randomised inputs and assert the same rules hold as
  // *invariants*, checked against an independent oracle. Each property
  // re-derives its cases from a fixed seed, so a failure is reproducible.

  final results = <Map<String, dynamic>>[];
  void record(String name, bool passed, int ms, [String? error]) {
    results.add({
      'name': name,
      'status': passed ? 'pass' : 'fail',
      'duration_ms': ms,
      if (error != null) 'error': error,
    });
  }

  tearDownAll(() async {
    await TestReporter.reportTestResults('ics_export', results);
  });

  group('RFC 5545 text escaping', () {
    test('commas, semicolons and backslashes in titles are escaped', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(sectionId: 'L1')],
        [makeCourse(courseTitle: r'Data, Structures; & Algo\Lab')],
        options: const ExportOptions(showCourseCode: false),
      );

      // The SUMMARY value must carry escaped separators, never raw ones.
      final summary = _unfold(ics)
          .split('\r\n')
          .firstWhere((l) => l.startsWith('SUMMARY:'));
      expect(summary, contains(r'\,'));
      expect(summary, contains(r'\;'));
      expect(summary, contains(r'\\'));
      // No *unescaped* comma/semicolon leaks into the text value.
      final value = summary.substring('SUMMARY:'.length);
      expect(_hasUnescaped(value, ','), isFalse, reason: value);
      expect(_hasUnescaped(value, ';'), isFalse, reason: value);
    });

    test('a newline in a field is escaped, not emitted as a line break', () {
      final ics = ExportService.buildIcsContent(
        [makeSelectedSection(sectionId: 'L1')],
        [makeCourse(courseTitle: 'Line one\nLine two')],
      );
      final summary = _unfold(ics)
          .split('\r\n')
          .firstWhere((l) => l.startsWith('SUMMARY:'));
      expect(summary, contains(r'\n'));
      // The whole SUMMARY stays on one logical line (no structural break).
      expect(summary, contains('Line one'));
      expect(summary, contains('Line two'));
    });
  });

  group('structural well-formedness (randomised)', () {
    test('every generated calendar is structurally valid', () {
      final sw = Stopwatch()..start();
      const trials = 400;
      try {
        for (var t = 0; t < trials; t++) {
          final r = Random(0x1C5 + t);
          final (sections, courses) = _randomTimetable(r);
          final ics = ExportService.buildIcsContent(
            sections,
            courses,
            timetableId: 'tt$t',
            calendarName: _maybeSpicyName(r),
            options: _randomOptions(r),
            campusId: 'hyderabad',
          );

          final ctx = 'seed=${0x1C5 + t}';
          expect(ics, startsWith('BEGIN:VCALENDAR'), reason: ctx);
          expect(ics.trimRight(), endsWith('END:VCALENDAR'), reason: ctx);

          // Balanced component blocks.
          for (final comp in ['VCALENDAR', 'VEVENT', 'VALARM', 'VTIMEZONE']) {
            expect(_count(ics, 'BEGIN:$comp'), _count(ics, 'END:$comp'),
                reason: '$ctx unbalanced $comp');
          }

          // CRLF-only: the only newline chars are line separators.
          expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse,
              reason: '$ctx bare LF');

          // Every physical line is within the fold limit.
          for (final line in ics.split('\r\n')) {
            expect(line.length <= 75, isTrue,
                reason: '$ctx overlong line (${line.length}): $line');
          }

          // Every event carries a UID and a DTSTART; UIDs are unique.
          final uids = <String>[];
          for (final ev in _vevents(ics)) {
            final lines = ev.split('\n');
            expect(lines.any((l) => l.startsWith('UID:')), isTrue,
                reason: '$ctx event without UID');
            expect(lines.any((l) => l.startsWith('DTSTART')), isTrue,
                reason: '$ctx event without DTSTART');
            uids.add(lines.firstWhere((l) => l.startsWith('UID:')));

            // Timed events: DTEND must not precede DTSTART.
            final start = _stamp(lines, 'DTSTART');
            final end = _stamp(lines, 'DTEND');
            if (start != null && end != null) {
              expect(end.compareTo(start) >= 0, isTrue,
                  reason: '$ctx DTEND < DTSTART ($start > $end)');
            }
          }
          expect(uids.toSet().length, uids.length, reason: '$ctx duplicate UID');
        }
        sw.stop();
        record('structural well-formedness', true, sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        record('structural well-formedness', false, sw.elapsedMilliseconds,
            e.toString());
        rethrow;
      }
    });
  });
}



// ── helpers ──────────────────────────────────────────────────────────────────

String _unfold(String ics) => ics.replaceAll('\r\n ', '');

int _count(String s, String needle) =>
    needle.allMatches(s).length;

/// Whether [text] contains [ch] not preceded by an odd run of backslashes
/// (i.e. a genuinely unescaped separator).
bool _hasUnescaped(String text, String ch) {
  for (var i = 0; i < text.length; i++) {
    if (text[i] != ch) continue;
    var backslashes = 0;
    var j = i - 1;
    while (j >= 0 && text[j] == r'\') {
      backslashes++;
      j--;
    }
    if (backslashes.isEven) return true;
  }
  return false;
}

/// Compact timestamp (YYYYMMDDTHHMMSS or YYYYMMDD) from a DTSTART/DTEND line,
/// or null when the property has no such line.
String? _stamp(List<String> lines, String prop) {
  final line = lines.where((l) => l.startsWith(prop)).cast<String?>().firstWhere(
        (l) => l != null,
        orElse: () => null,
      );
  if (line == null) return null;
  return line.substring(line.lastIndexOf(':') + 1);
}

List<String> _vevents(String ics) {
  final unfolded = _unfold(ics);
  final blocks = <String>[];
  StringBuffer? current;
  for (final line in unfolded.split('\r\n')) {
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

// ── random timetable generation ──────────────────────────────────────────────

const _titles = [
  'Intro',
  r'Data, Structures',
  'Signals; Systems',
  r'Back\slash Lab',
  'Café ☕ 数学 🎓',
  'A very long course title that on its own comfortably exceeds seventy-five '
      'characters to force the folder to split it across continuation lines',
];

(List<SelectedSection>, List<Course>) _randomTimetable(Random r) {
  final n = 1 + r.nextInt(5);
  final sections = <SelectedSection>[];
  final courses = <Course>[];
  for (var i = 0; i < n; i++) {
    final code = 'C$i';
    final dayCount = 1 + r.nextInt(3);
    final days = <DayOfWeek>{};
    while (days.length < dayCount) {
      days.add(DayOfWeek.values[r.nextInt(DayOfWeek.values.length)]);
    }
    final startHour = 1 + r.nextInt(6);
    final hours = [startHour, if (r.nextBool()) startHour + 1];
    final section = makeSection(
      sectionId: 'L$i',
      days: days.toList(),
      hours: hours,
      room: r.nextBool() ? 'F${100 + i}' : 'Lab; ${i}A',
    );
    sections.add(makeSelectedSection(
        courseCode: code, sectionId: 'L$i', section: section));
    courses.add(makeCourse(
      courseCode: code,
      courseTitle: _titles[r.nextInt(_titles.length)],
      sections: [section],
      midSemExam:
          r.nextBool() ? makeExam(date: DateTime(2026, 3, 1 + r.nextInt(20))) : null,
      endSemExam:
          r.nextBool() ? makeExam(date: DateTime(2026, 5, 1 + r.nextInt(20))) : null,
    ));
  }
  return (sections, courses);
}

ExportOptions _randomOptions(Random r) => ExportOptions(
      showCourseCode: r.nextBool(),
      showCourseTitle: r.nextBool(),
      showSectionId: r.nextBool(),
      showInstructor: r.nextBool(),
      showRoom: r.nextBool(),
      showTimeSlots: r.nextBool(),
      showExamDates: r.nextBool(),
    );

String? _maybeSpicyName(Random r) =>
    r.nextBool() ? null : 'Sem, 2026; "quoted" \\ back';
