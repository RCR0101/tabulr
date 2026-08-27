import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';

import 'package:timetable_maker/widgets/courses_tab_widget.dart';

void main() {
  Widget harness() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 380,
        height: 700,
        child: CoursesTabWidget(
          courses: const [],
          selectedSections: const [],
          projectCount: 0,
          creditBasis: CreditBasis.units,
          onProjectCountChanged: (_) {},
          onSectionToggle: (_, __, ___) {},
        ),
      ),
    ),
  );

  testWidgets('uses Catalog and My Plan instead of three competing tabs', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    expect(find.text('Catalog  0'), findsOneWidget);
    expect(find.text('My Plan  0'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Exams'), findsNothing);

    await tester.tap(find.text('My Plan  0'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected courses'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Exams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
