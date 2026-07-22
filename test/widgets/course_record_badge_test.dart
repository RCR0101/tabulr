import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/widgets/common/course_record_badge.dart';

import '../models/academic_record_test.dart' show recordOf;

Future<void> pumpBadge(
  WidgetTester tester, {
  required AcademicRecord record,
  required String courseCode,
  bool showGrade = true,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CourseRecordBadge(
        record: record,
        courseCode: courseCode,
        showGrade: showGrade,
      ),
    ),
  ));
}

void main() {
  group('CourseRecordBadge', () {
    testWidgets('draws nothing for a student with no record', (tester) async {
      // This is what keeps every browser uncluttered for most users.
      await pumpBadge(
        tester,
        record: AcademicRecord.empty,
        courseCode: 'CS F211',
      );
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('draws nothing for a course the student never took',
        (tester) async {
      await pumpBadge(
        tester,
        record: recordOf({'CS F211': (grade: 'A', credits: 3)}),
        courseCode: 'MATH F211',
      );
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('ticks a cleared course and shows the grade', (tester) async {
      await pumpBadge(
        tester,
        record: recordOf({'CS F211': (grade: 'A-', credits: 3)}),
        courseCode: 'CS F211',
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('A-'), findsOneWidget);
    });

    testWidgets('matches regardless of how the code is spaced', (tester) async {
      await pumpBadge(
        tester,
        record: recordOf({'CSF211': (grade: 'B', credits: 3)}),
        courseCode: 'CS F211',
      );
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('marks a failed course differently from a cleared one',
        (tester) async {
      await pumpBadge(
        tester,
        record: recordOf({'CS F211': (grade: 'E', credits: 3)}),
        courseCode: 'CS F211',
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('omits the grade in dense rows', (tester) async {
      await pumpBadge(
        tester,
        record: recordOf({'CS F211': (grade: 'A', credits: 3)}),
        courseCode: 'CS F211',
        showGrade: false,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });
  });
}
