import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';
import 'package:timetable_maker/widgets/academic_calendar_list.dart';

/// Renders the academic-calendar agenda so the design can be looked at.
/// Writing the PNG is the point; there is nothing asserted here.
void main() {
  setUpAll(() async {
    final data = File('assets/fonts/Inter.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  });

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

  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    testWidgets('render academic calendar - $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, the tightest case.
      tester.view.physicalSize = const Size(820, 1700);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          brightness: brightness,
          colorSchemeSeed: const Color(0xFF58A6FF),
        ),
        home: Scaffold(body: AcademicCalendarAgenda(events: events)),
      ));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = tester.firstRenderObject(find.byType(RepaintBoundary));
        final image = await (boundary as dynamic).toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/goldens/academic_calendar_$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
