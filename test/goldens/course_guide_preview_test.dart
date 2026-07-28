import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/course_guide_service.dart';
import 'package:timetable_maker/widgets/course_guide_widget.dart';

import '../helpers/preview_harness.dart';

/// Renders the Course Guide's semester sections so the design can be looked at.
/// Writing the PNG is the point; there is nothing asserted here.
void main() {
  setUpAll(loadPreviewFont);

  CourseGuideEntry entry(String code, String name, double credits) =>
      CourseGuideEntry(code: code, name: name, credits: credits, type: 'Normal');

  // The awkward cases, or the preview flatters the design: a long title that
  // has to wrap, a three-way choice, a choice whose halves differ in credit,
  // and a fractional-unit lab.
  final semesters = <String, List<CourseGuideSlot>>{
    '2-2': [
      CourseGuideSlot([entry('BITS F225', 'Environmental Studies', 3)]),
      CourseGuideSlot([
        entry('ECON F211', 'Principles of Economics', 3),
        entry('MGTS F211', 'Principles of Management', 3),
      ]),
      CourseGuideSlot([entry('MF F219', 'Manufacturing Processes', 3)]),
      CourseGuideSlot([
        entry('MF F220', 'Computer Aided Design and Manufacturing Laboratory', 1.5),
      ]),
      CourseGuideSlot([
        entry('CS F211', 'Data Structures and Algorithms', 4),
        entry('CS F213', 'Object Oriented Programming', 3),
        entry('CS F214', 'Logic in Computer Science', 3),
      ]),
    ],
    '3-1': [
      CourseGuideSlot([entry('MF F311', 'Advanced Manufacturing Processes', 3)]),
      CourseGuideSlot([entry('MF F317', 'Production Planning and Control', 3)]),
      CourseGuideSlot([entry('MATH F212', 'Optimization', 3)]),
    ],
  };

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('course guide — $name', (tester) async {
      usePreviewSurface(tester, const Size(820, 1900));

      await tester.pumpWidget(
        MaterialApp(
          theme: previewTheme(brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final sem in semesters.keys)
                    CourseGuideSemesterCard(
                      semester: sem,
                      slots: semesters[sem]!,
                      initiallyExpanded: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await capturePreview(tester, 'course_guide_$name');
    });
  }
}
