import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';

// Same real Hyderabad 2026-27 rows as functions/test/ics.test.js, so the app
// calendar and the .ics feed are held to the same answers.
AcademicCalendarEvent ev(String date, String label, AcademicEventCategory c, {String? end}) =>
    AcademicCalendarEvent(
      date: DateTime.parse(date),
      endDate: end == null ? null : DateTime.parse(end),
      label: label,
      category: c,
    );

final hyd = [
  ev('2026-08-03', 'Class work begins', AcademicEventCategory.milestone),
  ev('2026-08-15', 'Independence Day (H)', AcademicEventCategory.holiday),
  ev('2026-08-17', 'Last day for substitution of courses', AcademicEventCategory.deadline),
  ev('2026-10-02', 'Gandhi Jayanti (H)', AcademicEventCategory.holiday),
  ev('2026-10-05', 'Mid sem Exam (Classwork Suspendedl)', AcademicEventCategory.exam, end: '2026-10-10'),
  ev('2026-10-23', 'ATMOS - 2026 (Class work Suspended)', AcademicEventCategory.milestone, end: '2026-10-25'),
  ev('2026-11-27', 'Last day of classes', AcademicEventCategory.deadline),
];

bool has(String d, [List<AcademicCalendarEvent>? events]) => hasClassOn(
      events ?? hyd,
      DateTime.parse(d),
      semesterStart: DateTime(2026, 8, 3),
      semesterEnd: DateTime(2026, 12, 18),
    );

void main() {
  test('an ordinary teaching day has class', () {
    expect(has('2026-08-17'), isTrue, reason: 'a deadline is not a day off');
    expect(has('2026-10-16'), isTrue);
  });

  test('holidays, suspended classwork and the mid-sem week do not', () {
    expect(has('2026-08-15'), isFalse);
    expect(has('2026-10-02'), isFalse);
    expect(has('2026-10-07'), isFalse);
    expect(has('2026-10-23'), isFalse);
  });

  test('nothing before classes begin or after the last day of classes', () {
    expect(has('2026-08-01'), isFalse);
    expect(has('2026-08-03'), isTrue);
    expect(has('2026-11-27'), isTrue);
    expect(has('2026-11-30'), isFalse, reason: 'between last class and compre');
  });

  test('without calendar rows the admin semester dates bound the term', () {
    expect(has('2026-12-10', const []), isTrue);
    expect(has('2026-12-19', const []), isFalse);
  });
}
