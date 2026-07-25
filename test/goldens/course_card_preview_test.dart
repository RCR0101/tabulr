import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/course_list_widget.dart';
import '../helpers/test_data.dart';

/// Renders the course card to a PNG so the design can be looked at rather than
/// argued about. Not an assertion — writing the file IS the point.
///
///   flutter test test/goldens/course_card_preview_test.dart
///   open test/goldens/course_card.png
void main() {
  setUpAll(() async {
    // flutter test ships a placeholder font that draws every glyph as a filled
    // box, which makes a design preview useless. Load the real bundled Inter.
    final data = File('assets/fonts/Inter.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  });

  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
  testWidgets('render the card - \$name', (tester) async {
    tester.view.physicalSize = const Size(820, 1500);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cs = makeCourse(
      courseCode: 'CS F301',
      courseTitle: 'Principles of Programming Languages',
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
            hours: [3],
            instructor: 'SUNDAR B',
            room: 'F102'),
        makeSection(
            sectionId: 'L2',
            days: [DayOfWeek.T, DayOfWeek.Th],
            hours: [5],
            // Three names: the case that used to ellipsise away.
            instructor: 'RAJESH KUMAR, Priya Nair, S Venkatesh',
            room: 'D201'),
        makeSection(
            sectionId: 'T1',
            type: SectionType.T,
            days: [DayOfWeek.W],
            hours: [6],
            instructor: 'SUNDAR B, Anita Rao',
            room: 'F105'),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
      endSemExam: makeExam(date: DateTime(2026, 5, 12), timeSlot: TimeSlot.FN),
    );
    final math = makeCourse(
      courseCode: 'MATH F211',
      courseTitle: 'Mathematics III',
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
            hours: [3],
            instructor: 'A K SHARMA',
            room: 'F101'),
      ],
      midSemExam: makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1),
    );
    final bio = makeCourse(
      courseCode: 'BIO F111',
      courseTitle: 'General Biology',
      sections: [
        makeSection(
            sectionId: 'L1',
            days: [DayOfWeek.T, DayOfWeek.Th],
            hours: [2],
            instructor: 'P MEENA',
            room: 'A305'),
      ],
    );

    // One course partly added (so a sibling reads "already chosen"), one that
    // clashes outright, one plain.
    final selected = [
      SelectedSection(
          courseCode: 'CS F301',
          sectionId: 'L1',
          section: cs.sections.first),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF58A6FF),
      ),
      home: Scaffold(
        body: CourseListWidget(
          courses: [cs, math, bio],
          catalog: [cs, math, bio],
          selectedSections: selected,
          onSectionToggle: (_, __, ___) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Expand the first card so the section rows are visible in the shot.
    await tester.tap(find.text('CS F301'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = tester.firstRenderObject(find.byType(RepaintBoundary));
      final image = await (boundary as dynamic).toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('test/goldens/course_card_$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
  }
}
