import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/screens/add_swap_screen.dart';

import '../helpers/preview_harness.dart';
import '../helpers/test_data.dart';

/// Renders Add/Swap at phone width so the layout can be looked at. Writing the
/// PNG is the point; nothing is asserted.
///
/// The fixture carries the cases that actually crowd the screen: a course with
/// all three components selected, a title long enough to wrap twice at 410
/// logical pixels, and both exam rows present — the tab flatters itself on one
/// tidy card.
void main() {
  setUpAll(loadPreviewFont);

  final courses = <Course>[
    makeCourse(
      courseCode: 'CS F211',
      courseTitle: 'Data Structures and Algorithms',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M, DayOfWeek.W], hours: [2]),
        makeSection(
            sectionId: 'T1',
            type: SectionType.T,
            days: [DayOfWeek.F],
            hours: [4],
            instructor: 'BIJU K RAVEENDRAN'),
        makeSection(
            sectionId: 'P1',
            type: SectionType.P,
            days: [DayOfWeek.Th],
            hours: [7, 8],
            instructor: 'APURBA DAS'),
      ],
      midSemExam: ExamSchedule(
          date: DateTime(2026, 10, 8), timeSlot: TimeSlot.MS2),
      endSemExam: ExamSchedule(
          date: DateTime(2026, 12, 15), timeSlot: TimeSlot.FN),
    ),
    makeCourse(
      courseCode: 'PHY F213',
      courseTitle: 'Optics and Modern Physics for Engineering Applications',
      sections: [
        makeSection(
            sectionId: 'L2',
            days: [DayOfWeek.T, DayOfWeek.Th],
            hours: [1],
            instructor: 'RAJNEESH KUMAR MISHRA'),
      ],
      midSemExam: ExamSchedule(
          date: DateTime(2026, 10, 9), timeSlot: TimeSlot.MS1),
      endSemExam: ExamSchedule(
          date: DateTime(2026, 12, 18), timeSlot: TimeSlot.AN),
    ),
    makeCourse(
      courseCode: 'ECON F211',
      courseTitle: 'Principles of Economics',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [5]),
      ],
    ),
  ];

  final selected = [
    for (final c in courses)
      for (final s in c.sections)
        makeSelectedSection(
            courseCode: c.courseCode, sectionId: s.sectionId, section: s),
  ];

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('add swap phone — $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, under the 600px
      // breakpoint, so this is the tabbed mobile layout.
      usePreviewSurface(tester, const Size(820, 1500));

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: AddSwapScreen(
            currentSelectedSections: selected,
            availableCourses: courses,
            currentCampus: 'hyderabad',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'add_swap_phone_$name');
    });

    testWidgets('add swap phone browse — $name', (tester) async {
      usePreviewSurface(tester, const Size(820, 1500));

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: AddSwapScreen(
            currentSelectedSections: selected,
            availableCourses: courses,
            currentCampus: 'hyderabad',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add/Swap'));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'add_swap_browse_$name');
    });
  }
}
