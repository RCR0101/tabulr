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

    testWidgets('names the clashing courses and the exam date', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([examClash()]));

      expect(find.text('This timetable has 1 exam clash'), findsOneWidget);
      expect(
        find.text('Exam Clash (CS F214, ECE F211) on 15 Dec'),
        findsOneWidget,
      );
    });

    testWidgets('lists one line per exam clash', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([
        examClash(),
        examClash(date: DateTime(2026, 10, 6)),
      ]));

      expect(
        find.text('Exam Clash (CS F214, ECE F211) on 15 Dec'),
        findsOneWidget,
      );
      expect(
        find.text('Exam Clash (CS F214, ECE F211) on 6 Oct'),
        findsOneWidget,
      );
    });

    testWidgets('omits the date when the warning has none', (tester) async {
      await tester.pumpWidget(wrapAsInEditor([
        ClashWarning(
          type: ClashType.midSemExam,
          message: 'MidSem exam clash',
          conflictingCourses: const ['CS F214', 'ECE F211'],
          severity: ClashSeverity.error,
        ),
      ]));

      expect(find.text('Exam Clash (CS F214, ECE F211)'), findsOneWidget);
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

    testWidgets('shows no exam line when only class clashes exist',
        (tester) async {
      await tester.pumpWidget(wrapAsInEditor([classClash()]));

      expect(find.text('This timetable has 1 class clash'), findsOneWidget);
      expect(find.textContaining('Exam Clash ('), findsNothing);
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
      expect(tester.takeException(), isNull);

      final size = tester.getSize(find.byType(ClashWarningsWidget));
      expect(size.height, lessThan(400));
    });
  });
}
