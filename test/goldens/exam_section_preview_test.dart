import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/exam_dates_widget.dart';
import '../helpers/test_data.dart';

/// Renders the exam section so the design can be looked at. Writing the PNG is
/// the point; there is nothing asserted here.
void main() {
  setUpAll(() async {
    final data = File('assets/fonts/Inter.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  });

  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    testWidgets('render exams - $name', (tester) async {
      tester.view.physicalSize = const Size(820, 900);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final courses = [
        makeCourse(
          courseCode: 'CS F301',
          courseTitle: 'Principles of Programming Languages',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
          endSemExam:
              makeExam(date: DateTime(2026, 5, 12), timeSlot: TimeSlot.FN),
        ),
        // Same midsem day as CS F301 — the clash the old table never flagged.
        makeCourse(
          courseCode: 'MATH F211',
          courseTitle: 'Mathematics III',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS3),
          endSemExam:
              makeExam(date: DateTime(2026, 5, 16), timeSlot: TimeSlot.AN),
        ),
        // No compre — the em-dash state.
        makeCourse(
          courseCode: 'BITS F225',
          courseTitle: 'Environmental Studies',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 14), timeSlot: TimeSlot.MS2),
        ),
        makeCourse(
          courseCode: 'PHY F211',
          courseTitle: 'Classical Mechanics',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS1),
          endSemExam:
              makeExam(date: DateTime(2026, 5, 14), timeSlot: TimeSlot.FN),
        ),
        makeCourse(
          courseCode: 'HSS F236',
          courseTitle: 'Introduction to Film Studies',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 16), timeSlot: TimeSlot.MS4),
          endSemExam:
              makeExam(date: DateTime(2026, 5, 18), timeSlot: TimeSlot.AN),
        ),
        makeCourse(
          courseCode: 'ECON F211',
          courseTitle: 'Principles of Economics',
          midSemExam:
              makeExam(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS3),
          endSemExam:
              makeExam(date: DateTime(2026, 5, 20), timeSlot: TimeSlot.FN),
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          brightness: brightness,
          colorSchemeSeed: const Color(0xFF58A6FF),
        ),
        home: Scaffold(
          body: ExamDatesWidget(
            courses: courses,
            selectedSections: [
              for (final c in courses)
                SelectedSection(
                  courseCode: c.courseCode,
                  sectionId: 'L1',
                  section: c.sections.first,
                ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = tester.firstRenderObject(find.byType(RepaintBoundary));
        final image = await (boundary as dynamic).toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/goldens/exam_section_$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
