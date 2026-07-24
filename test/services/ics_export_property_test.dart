import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/export_options.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/ui/export_service.dart';
import '../helpers/test_data.dart';
import '../helpers/test_reporter.dart';

/// Property / edge tests for [ExportService.buildIcsContent].
///
/// ics_export_test.dart pins the behaviours (VTIMEZONE, alarms, hour-merging,
/// stable UIDs, folding). This adds the two things a calendar client is
/// unforgiving about and that the example tests don't reach: RFC 5545 text
/// *escaping* of course titles containing commas/semicolons/backslashes, and
/// structural well-formedness (balanced BEGIN/END, CRLF endings, ≤75-char
/// physical lines, a UID + DTSTART per event, unique UIDs) across hundreds of
/// randomised timetables.
void main() {
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
    await TestReporter.reportTestResults('ics_export_property', results);
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
