import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/courses_tab_widget.dart';

import '../helpers/preview_harness.dart';
import '../helpers/test_data.dart';

/// Renders the two new pieces — the "offered two ways" chooser on a course
/// card, and the mixed-basis warning above the credits bar — so the design can
/// be looked at rather than argued about. Not an assertion; the PNG is the
/// deliverable.
///
///   flutter test test/goldens/credit_hours_preview_test.dart
///   open test/goldens/credit_hours_light.png
void main() {
  setUpAll(loadPreviewFont);

  /// CS G569 as the 2026-27 Pilani booklet prints it: com 2986 at 4 units,
  /// com 6221 at 12 credit hours, identical sections.
  Course agenticAi() => Course.fromJson({
        'courseCode': 'CS G569',
        'courseTitle': 'Agentic AI',
        'lecture_credits': 0,
        'practical_credits': 0,
        'total_credits': 4,
        'total_credit_hours': 12,
        'com_codes': [2986, 6221],
        'variants': [
          {'com_code': 2986, 'credits': 4, 'credit_hours': 0},
          {'com_code': 6221, 'credits': 0, 'credit_hours': 12},
        ],
        'sections': [
          makeSection(
                  sectionId: 'L1',
                  days: [DayOfWeek.T, DayOfWeek.Th, DayOfWeek.F],
                  hours: [2],
                  instructor: 'DHRUV KUMAR',
                  room: '6101')
              .toJson(),
          makeSection(
                  sectionId: 'P1',
                  type: SectionType.P,
                  days: [DayOfWeek.T],
                  hours: [7, 8],
                  instructor: 'Kartikey Singh Bhandari',
                  room: '6016')
              .toJson(),
        ],
      });

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render the credit-hours UI - $name', (tester) async {
      usePreviewSurface(tester, const Size(880, 1500));

      final agentic = agenticAi();
      final cs = makeCourse(
        courseCode: 'CS F211',
        courseTitle: 'Data Structures and Algorithms',
        lectureCredits: 3,
        practicalCredits: 1,
        sections: [
          makeSection(
              sectionId: 'L1',
              days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
              hours: [3],
              instructor: 'SUNDAR B',
              room: 'F102'),
        ],
      );

      // The state worth showing: a credit-hours timetable, where every card
      // reports on that basis and the bar drops the /25 it cannot measure
      // against.
      final selected = [
        SelectedSection(
            courseCode: 'CS F211',
            sectionId: 'L1',
            section: cs.sections.first),
        SelectedSection(
            courseCode: 'CS G569',
            sectionId: 'L1',
            section: agentic.sections.first,
            comCode: 6221),
      ];

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        // The editor's courses tab whole: the mix warning, the credits bar
        // beneath it, and the cards with the chooser in the Search tab.
        home: Scaffold(
          body: CoursesTabWidget(
            courses: [agentic, cs],
            selectedSections: selected,
            onSectionToggle: (_, __, ___) {},
            projectCount: 0,
            onProjectCountChanged: (_) {},
            creditBasis: CreditBasis.hours,
            onRemoveBasis: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'credit_hours_$name');
    });
  }
}
