import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/clash_warnings_widget.dart';

void main() {
  /// Mirrors buildTimetablePanel: the widget sits in a Card that is a non-flex
  /// child of a Column, so it is laid out with unbounded height.
  Widget wrapAsInEditor(List<ClashWarning> warnings) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Card(child: ClashWarningsWidget(warnings: warnings)),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );

  ClashWarning examClash({DateTime? date}) => ClashWarning(
        type: ClashType.endSemExam,
        message: 'EndSem exam clash on 15 Dec FN',
        conflictingCourses: const ['CS F214', 'ECE F211'],
        severity: ClashSeverity.error,
        examDate: date ?? DateTime(2026, 12, 15),
      );

  ClashWarning classClash() => ClashWarning(
        type: ClashType.regularClass,
        message: 'Class time clash on Tuesday at 11:00-11:50 AM',
        conflictingCourses: const ['CS F111', 'MATH F112'],
        severity: ClashSeverity.error,
      );

  group('ClashWarningsWidget', () {
    testWidgets('lays out under unbounded height', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([examClash()]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts collapsed to the summary alone', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([examClash()]));

      expect(find.text('This timetable has 1 exam clash'), findsOneWidget);
      expect(find.text('EndSem exam clash on 15 Dec FN'), findsNothing);
    });

    testWidgets('expanding lists every clash', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([examClash(), classClash()]));

      await tester.tap(find.text('This timetable has 1 exam clash '
          'and 1 class clash'));
      await tester.pumpAndSettle();

      expect(find.text('EndSem exam clash on 15 Dec FN'), findsOneWidget);
      expect(
        find.text('Class time clash on Tuesday at 11:00-11:50 AM'),
        findsOneWidget,
      );
      expect(find.text('Courses: CS F214, ECE F211'), findsOneWidget);
    });

    testWidgets('summarises mixed clash types with plurals', (tester) async {
      await tester.pumpWidget(
        wrapAsInEditor([examClash(), examClash(), classClash()]),
      );

      expect(
        find.text('This timetable has 2 exam clashes and 1 class clash'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing when there are no warnings', (tester) async {
      await tester.pumpWidget(wrapAsInEditor(const []));

      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('This timetable has'), findsNothing);
    });

    testWidgets('scrolls rather than growing without bound', (tester) async {
      await tester.pumpWidget(
        wrapAsInEditor(List.generate(20, (_) => examClash())),
      );
      await tester.tap(find.text('This timetable has 20 exam clashes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final size = tester.getSize(find.byType(ClashWarningsWidget));
      expect(size.height, lessThan(400));
    });
  });
}
