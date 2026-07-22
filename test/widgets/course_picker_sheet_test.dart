import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';
import 'package:timetable_maker/widgets/common/course_picker_sheet.dart';

CourseMasterEntry entry(String code, String title, double credits) =>
    CourseMasterEntry(
      courseCode: code,
      title: title,
      credits: credits,
      type: 'Normal',
    );

/// Whatever the picker resolved to, filled in once it closes.
class PickerCapture {
  List<CourseMasterEntry>? picked;
  bool resolved = false;
}

/// Pumps a host with a button that opens the picker.
Future<PickerCapture> pumpPicker(
  WidgetTester tester, {
  Set<String> alreadyChosen = const {},
}) async {
  final capture = PickerCapture();

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            capture.picked = await showCoursePicker(
              context,
              alreadyChosen: alreadyChosen,
            );
            capture.resolved = true;
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ));

  return capture;
}

void main() {
  setUp(() {
    CoursesMasterService().seedForTest([
      entry('CS F211', 'Data Structures and Algorithms', 4),
      entry('CS F320', 'Foundations of Data Science', 3),
      entry('MATH F211', 'Mathematics III', 3),
      entry('BITS F225', 'Environmental Studies', 3),
    ]);
  });

  tearDown(() => CoursesMasterService().resetForTest());

  group('showCoursePicker', () {
    testWidgets('lists the campus catalogue', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('CS F211'), findsOneWidget);
      expect(find.text('Foundations of Data Science'), findsOneWidget);
    });

    testWidgets('filters on code and on title', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'MATH');
      await tester.pumpAndSettle();
      expect(find.text('MATH F211'), findsOneWidget);
      expect(find.text('CS F211'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Environmental');
      await tester.pumpAndSettle();
      expect(find.text('BITS F225'), findsOneWidget);
      expect(find.text('MATH F211'), findsNothing);
    });

    testWidgets('returns every course selected in one pass', (tester) async {
      // Multi-select is the point: a group is five to a dozen courses, and
      // reopening a dialog per course is what made the text box preferable.
      final capture = await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CS F211'));
      await tester.tap(find.text('CS F320'));
      await tester.pumpAndSettle();

      expect(find.text('Add 2 courses'), findsOneWidget);
      await tester.tap(find.text('Add 2 courses'));
      await tester.pumpAndSettle();

      expect(capture.resolved, isTrue);
      expect(capture.picked?.map((c) => c.courseCode), ['CS F211', 'CS F320']);
    });

    testWidgets('cannot add a course the minor already lists', (tester) async {
      // No course may count toward a minor twice.
      await pumpPicker(tester, alreadyChosen: {'CS F211'});
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('CS F211'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(tile.value, isTrue, reason: 'should read as already included');
      expect(tile.onChanged, isNull, reason: 'should be locked');
    });

    testWidgets('matches already-chosen codes however they are spaced',
        (tester) async {
      // Seeded minors spell codes the Bulletin's way; the catalogue may not.
      await pumpPicker(tester, alreadyChosen: {'CSF211'});
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('CS F211'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(tile.onChanged, isNull);
    });

    testWidgets('cannot confirm without a selection', (tester) async {
      final capture = await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Prompts rather than offering a count, and tapping it does nothing.
      expect(find.text('Select courses'), findsOneWidget);
      await tester.tap(find.text('Select courses'));
      await tester.pumpAndSettle();

      expect(capture.resolved, isFalse);
      expect(find.text('Select courses'), findsOneWidget,
          reason: 'sheet should still be open');
    });

    testWidgets('deselecting takes the course back off', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 course'), findsOneWidget);

      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();
      expect(find.text('Select courses'), findsOneWidget);
    });

    testWidgets('says so when the catalogue has not loaded', (tester) async {
      CoursesMasterService().resetForTest();
      await pumpPicker(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Catalogue unavailable'), findsOneWidget);
    });
  });
}
