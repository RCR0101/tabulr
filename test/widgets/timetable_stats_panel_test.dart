import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/widgets/timetable_stats_panel.dart';

import '../helpers/test_data.dart';

Future<void> _pump(WidgetTester tester, List<Course> courses) async {
  tester.view.physicalSize = const Size(820, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TimetableStatsPanel(timetable: makeTimetable(courses: courses))),
  ));
  await tester.pumpAndSettle();
}

Course _course(String code, {
  required double lecture,
  double practical = 0,
  List<DayOfWeek> days = const [DayOfWeek.M],
  List<int> hours = const [3],
}) =>
    makeCourse(
      courseCode: code,
      lectureCredits: lecture,
      practicalCredits: practical,
      sections: [makeSection(sectionId: 'L1', days: days, hours: hours)],
    );

void main() {
  testWidgets('credits are shown against the semester cap', (tester) async {
    await _pump(tester, [
      _course('CS F211', lecture: 3, practical: 1),
      _course('MATH F211', lecture: 3, days: [DayOfWeek.T]),
    ]);

    expect(find.text('Credits (/25)'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // Under the cap, so no warning.
    expect(find.text('over cap'), findsNothing);
  });

  testWidgets('going over the cap says so in words', (tester) async {
    await _pump(tester, [
      _course('CS F211', lecture: 20, practical: 4),
      _course('MATH F211', lecture: 3, days: [DayOfWeek.T]),
    ]);

    expect(find.text('27'), findsOneWidget);
    expect(find.text('over cap'), findsOneWidget);
  });

  testWidgets('whole credits are not printed with a decimal', (tester) async {
    await _pump(tester, [_course('CS F211', lecture: 3)]);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('3.0'), findsNothing);
  });

  testWidgets('an 8 AM start is called out; otherwise it says there is none',
      (tester) async {
    await _pump(tester, [
      _course('CS F211', lecture: 3, days: [DayOfWeek.M, DayOfWeek.W], hours: [1]),
    ]);
    expect(find.text('8 AM start on Mon, Wed'), findsOneWidget);
    expect(find.text('No 8 AM classes'), findsNothing);
  });

  testWidgets('a week with no 8 AM class says so', (tester) async {
    await _pump(tester, [_course('CS F211', lecture: 3, hours: [4])]);
    expect(find.text('No 8 AM classes'), findsOneWidget);
  });

  testWidgets('course and hour counts are shown', (tester) async {
    await _pump(tester, [
      _course('CS F211', lecture: 3, hours: [2, 3]),
      _course('MATH F211', lecture: 3, days: [DayOfWeek.T], hours: [2]),
    ]);

    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Hours / week'), findsOneWidget);
    // 2 hours Monday + 1 Tuesday.
    expect(find.text('3'), findsWidgets);
  });
}
