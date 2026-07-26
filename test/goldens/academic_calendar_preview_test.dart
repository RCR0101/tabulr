import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';
import 'package:timetable_maker/widgets/academic_calendar_list.dart';

import '../helpers/preview_harness.dart';

/// Renders the academic-calendar agenda so the design can be looked at.
/// Writing the PNG is the point; there is nothing asserted here.
void main() {
  setUpAll(loadPreviewFont);

  // Dates are relative to today so the countdown column is exercised the same
  // way whenever the preview is regenerated.
  final today = DateTime.now();
  DateTime inDays(int d) =>
      DateTime(today.year, today.month, today.day).add(Duration(days: d));

  final events = <AcademicCalendarEvent>[
    AcademicCalendarEvent(
      date: inDays(-21),
      label: 'Classwork begins',
      category: AcademicEventCategory.milestone,
    ),
    AcademicCalendarEvent(
      date: inDays(-4),
      label: 'Last date to drop a course',
      category: AcademicEventCategory.deadline,
    ),
    // Spans today — the "On now" state.
    AcademicCalendarEvent(
      date: inDays(-1),
      endDate: inDays(3),
      label: 'Mid-semester examinations',
      category: AcademicEventCategory.exam,
    ),
    AcademicCalendarEvent(
      date: inDays(1),
      label: 'Holi',
      category: AcademicEventCategory.holiday,
    ),
    AcademicCalendarEvent(
      date: inDays(6),
      label: 'Last date for withdrawal from a course with a W grade',
      category: AcademicEventCategory.deadline,
    ),
    AcademicCalendarEvent(
      date: inDays(12),
      endDate: inDays(14),
      label: 'Oasis — cultural festival',
      category: AcademicEventCategory.event,
    ),
    AcademicCalendarEvent(
      date: inDays(40),
      label: 'Ambedkar Jayanti',
      category: AcademicEventCategory.holiday,
    ),
    AcademicCalendarEvent(
      date: inDays(55),
      endDate: inDays(62),
      label: 'Comprehensive examinations',
      category: AcademicEventCategory.exam,
    ),
    AcademicCalendarEvent(
      date: inDays(70),
      label: 'Semester ends',
      category: AcademicEventCategory.milestone,
    ),
  ]..sort((a, b) => a.date.compareTo(b.date));

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render academic calendar - $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, the tightest case.
      usePreviewSurface(tester, const Size(820, 1700));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: Scaffold(body: AcademicCalendarAgenda(events: events)),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'academic_calendar_$name');
    });
  }
}
