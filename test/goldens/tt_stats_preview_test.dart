import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/timetable_stats_panel.dart';
import '../helpers/test_data.dart';

/// Renders the TT Stats panel so the design can be looked at. Writing the PNG
/// is the point; there is nothing asserted here.
void main() {
  setUpAll(() async {
    final data = File('assets/fonts/Inter.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  });

  // A deliberately awkward week: 8 AM starts, a lab that eats lunch, a long
  // back-to-back run, a Saturday tutorial, and a gap on Tuesday.
  final courses = [
    makeCourse(
      courseCode: 'CS F211',
      courseTitle: 'Data Structures & Algorithms',
      lectureCredits: 3,
      practicalCredits: 1,
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
            hours: [1]),
        makeSection(
            sectionId: 'P1',
            type: SectionType.P,
            days: [DayOfWeek.W],
            hours: [5, 6]),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
      endSemExam: makeExam(date: DateTime(2026, 5, 12), timeSlot: TimeSlot.FN),
    ),
    makeCourse(
      courseCode: 'MATH F211',
      courseTitle: 'Mathematics III',
      lectureCredits: 3,
      practicalCredits: 0,
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.T, DayOfWeek.Th],
            hours: [2, 3]),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
      endSemExam: makeExam(date: DateTime(2026, 5, 14), timeSlot: TimeSlot.AN),
    ),
    makeCourse(
      courseCode: 'EEE F111',
      courseTitle: 'Electrical Sciences',
      lectureCredits: 3,
      practicalCredits: 1,
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.M, DayOfWeek.W],
            hours: [2, 3, 4]),
        makeSection(
            sectionId: 'T1',
            type: SectionType.T,
            days: [DayOfWeek.S],
            hours: [4]),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 12), timeSlot: TimeSlot.MS1),
      endSemExam: makeExam(date: DateTime(2026, 5, 15), timeSlot: TimeSlot.FN),
    ),
    makeCourse(
      courseCode: 'BITS F225',
      courseTitle: 'Environmental Studies',
      lectureCredits: 3,
      practicalCredits: 0,
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [8]),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 13), timeSlot: TimeSlot.MS3),
    ),
    makeCourse(
      courseCode: 'HSS F236',
      courseTitle: 'Introduction to Film Studies',
      lectureCredits: 3,
      practicalCredits: 0,
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.Th], hours: [7, 8]),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 16), timeSlot: TimeSlot.MS4),
      endSemExam: makeExam(date: DateTime(2026, 5, 18), timeSlot: TimeSlot.AN),
    ),
  ];

  final timetable = Timetable(
    id: 'preview',
    name: 'Sem 1',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    campus: Campus.hyderabad,
    availableCourses: courses,
    selectedSections: [
      for (final c in courses)
        for (final s in c.sections)
          SelectedSection(
              courseCode: c.courseCode, sectionId: s.sectionId, section: s),
    ],
    clashWarnings: [],
  );

  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    testWidgets('render tt stats - $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, the tightest case.
      tester.view.physicalSize = const Size(820, 1900);
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
        home: Scaffold(body: TimetableStatsPanel(timetable: timetable)),
      ));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final boundary = tester.firstRenderObject(find.byType(RepaintBoundary));
        final image = await (boundary as dynamic).toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/goldens/tt_stats_$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
