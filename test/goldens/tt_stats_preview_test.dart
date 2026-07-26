import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/timetable_stats_panel.dart';

import '../helpers/preview_harness.dart';
import '../helpers/test_data.dart';

/// Renders the TT Stats panel so the design can be looked at. Writing the PNG
/// is the point; there is nothing asserted here.
void main() {
  setUpAll(loadPreviewFont);

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

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render tt stats - $name', (tester) async {
      // 820 physical at 2.0 is 410 logical — a phone, the tightest case.
      usePreviewSurface(tester, const Size(820, 1900));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: Scaffold(body: TimetableStatsPanel(timetable: timetable)),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'tt_stats_$name');
    });
  }
}
