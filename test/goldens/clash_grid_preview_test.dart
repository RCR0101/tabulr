import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_display.dart';
import 'package:timetable_maker/widgets/clash_warnings_widget.dart';
import 'package:timetable_maker/widgets/timetable/course_palette.dart';
import 'package:timetable_maker/widgets/timetable/timetable_grid.dart';

import '../helpers/preview_harness.dart';

/// Renders a week that carries clashes, so the side-by-side cell split and the
/// collapsed clash banner can be looked at. Writing the PNG is the point;
/// there is nothing asserted here.
void main() {
  setUpAll(loadPreviewFont);

  TimetableSlot slot({
    required DayOfWeek day,
    required List<int> hours,
    required String code,
    required String title,
    String section = 'L1',
    String instructor = 'Dr. A Sharma',
    String room = '6101',
  }) =>
      TimetableSlot(
        day: day,
        hours: hours,
        courseCode: code,
        courseTitle: title,
        sectionId: section,
        instructor: instructor,
        room: room,
      );

  // Monday hour 2: a plain two-way clash. Wednesday: a three-hour lab crossed
  // by two separate lectures, the case where lanes have to be shared.
  final slots = [
    slot(day: DayOfWeek.M, hours: [1], code: 'CS F211', title: 'Data Structures'),
    slot(day: DayOfWeek.M, hours: [2], code: 'CS F211', title: 'Data Structures'),
    slot(
        day: DayOfWeek.M,
        hours: [2],
        code: 'MATH F211',
        title: 'Mathematics III',
        instructor: 'Dr. B Rao',
        room: '2205'),
    slot(
        day: DayOfWeek.W,
        hours: [3, 4, 5],
        code: 'EEE F111',
        title: 'Electrical Sciences',
        section: 'P1',
        instructor: 'Dr. C Iyer',
        room: 'LAB-2'),
    slot(day: DayOfWeek.W, hours: [3], code: 'CS F211', title: 'Data Structures'),
    slot(
        day: DayOfWeek.W,
        hours: [5],
        code: 'HSS F236',
        title: 'Film Studies',
        instructor: 'Dr. D Menon',
        room: '3108'),
    slot(
        day: DayOfWeek.Th,
        hours: [4],
        code: 'MATH F211',
        title: 'Mathematics III',
        instructor: 'Dr. B Rao',
        room: '2205'),
  ];

  final warnings = [
    ClashWarning(
      type: ClashType.regularClass,
      message: 'Class time clash on Monday at 9:00-9:50 AM',
      conflictingCourses: const ['CS F211', 'MATH F211'],
      severity: ClashSeverity.error,
    ),
    ClashWarning(
      type: ClashType.regularClass,
      message: 'Class time clash on Wednesday at 10:00-10:50 AM',
      conflictingCourses: const ['EEE F111', 'CS F211'],
      severity: ClashSeverity.error,
    ),
    ClashWarning(
      type: ClashType.endSemExam,
      message: 'EndSem exam clash on 15 Dec FN',
      conflictingCourses: const ['CS F211', 'HSS F236'],
      severity: ClashSeverity.error,
      examDate: DateTime(2026, 12, 15),
    ),
  ];

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render clashing grid - $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, where a split cell is
      // tightest and the grid falls back to scrolling sideways.
      usePreviewSurface(tester, const Size(820, 1400));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: Scaffold(
          body: Column(
            children: [
              Card(child: ClashWarningsWidget(warnings: warnings)),
              Expanded(
                child: Builder(
                  builder: (context) => TimetableGrid(
                    slots: slots,
                    layout: TimetableLayout.vertical,
                    size: TimetableSize.medium,
                    palette: CoursePalette.forCourses(
                      context,
                      slots.map((s) => s.courseCode),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'clash_grid_$name');
    });
  }
}
