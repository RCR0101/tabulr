import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/widgets/timetable_generator_widget.dart';
import '../helpers/test_data.dart';

final _courses = [
  makeCourse(courseCode: 'CS F111', courseTitle: 'Computer Programming'),
  makeCourse(courseCode: 'MATH F111', courseTitle: 'Mathematics I'),
  makeCourse(
    courseCode: 'PHY F111',
    courseTitle: 'Mechanics Oscillations and Waves',
    sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [3])],
  ),
];

Widget _host({List<Course>? courses}) => MaterialApp(
      home: Scaffold(
        body: TimetableGeneratorWidget(
          availableCourses: courses ?? _courses,
          onTimetableSelected: (_) {},
        ),
      ),
    );

/// Types into the first course search field and taps the suggestion.
Future<void> _searchAndPick(WidgetTester tester, String query,
    {int fieldIndex = 0}) async {
  final field = find.byType(TextField).at(fieldIndex);
  await tester.enterText(field, query);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.text(query).last);
  await tester.pumpAndSettle();
}

void main() {
  // A wide surface so the desktop layout applies: configuration and results sit
  // side by side, which keeps both reachable without driving the mobile TabBar.
  // The config column is a third of the width, and its rows need real room.
  late final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(2400, 2000)
      ..devicePixelRatio = 1.0;
  });

  tearDown(() {
    binding.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  group('course selection', () {
    testWidgets('starts with both course lists empty', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('No mandatory courses'), findsOneWidget);
      expect(find.text('No optional courses'), findsOneWidget);
    });

    testWidgets('picking a course from search adds it to mandatory',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _searchAndPick(tester, 'CS F111');

      expect(find.text('No mandatory courses'), findsNothing);
      expect(find.text('CS F111'), findsWidgets);
    });

    testWidgets('credits in the header track the selection', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.textContaining('Mandatory Courses (0.0 credits)'),
          findsOneWidget);

      await _searchAndPick(tester, 'CS F111');

      expect(find.textContaining('Mandatory Courses (4.0 credits)'),
          findsOneWidget);
    });

    testWidgets('the chip delete button removes the course', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _searchAndPick(tester, 'CS F111');
      expect(find.byType(Chip), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(Chip),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Chip), findsNothing);
      expect(find.text('No mandatory courses'), findsOneWidget);
    });

    testWidgets('a course already mandatory is not added again as optional',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _searchAndPick(tester, 'CS F111');
      // Second field is the optional-course search.
      await _searchAndPick(tester, 'CS F111', fieldIndex: 1);

      expect(find.text('No optional courses'), findsOneWidget);
    });
  });

  group('constraints', () {
    testWidgets('back-to-back checkbox toggles', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final tile = find.ancestor(
        of: find.text('Avoid back-to-back classes'),
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
    });

    testWidgets('protecting lunch reveals its require toggle', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Require this (hard filter)'), findsNothing);

      await tester.tap(find.ancestor(
        of: find.text('Protect lunch break (12–2 PM)'),
        matching: find.byType(CheckboxListTile),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Require this (hard filter)'), findsOneWidget);
    });

    testWidgets('unprotecting lunch hides the require toggle again',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('Protect lunch break (12–2 PM)'),
        matching: find.byType(CheckboxListTile),
      );

      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text('Require this (hard filter)'), findsNothing);
    });

    testWidgets('the class-hours window starts unbounded', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Any time'), findsOneWidget);
    });
  });

  group('optional target selector', () {
    testWidgets('is hidden until there are two optionals', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.textContaining('Include:'), findsNothing);

      await _searchAndPick(tester, 'CS F111', fieldIndex: 1);
      expect(find.textContaining('Include:'), findsNothing);

      await _searchAndPick(tester, 'MATH F111', fieldIndex: 1);
      expect(find.text('Include: as many as fit'), findsOneWidget);
    });

    testWidgets('stepping down narrows the target', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _searchAndPick(tester, 'CS F111', fieldIndex: 1);
      await _searchAndPick(tester, 'MATH F111', fieldIndex: 1);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('Include: any 1 of 2'), findsOneWidget);
    });

    testWidgets('stepping back up returns to as-many-as-fit', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _searchAndPick(tester, 'CS F111', fieldIndex: 1);
      await _searchAndPick(tester, 'MATH F111', fieldIndex: 1);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('Include: as many as fit'), findsOneWidget);
    });
  });

  group('refine chips', () {
    /// Picks a mandatory course and generates, so the refine row exists.
    Future<void> generate(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, 'CS F111');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CS F111').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Timetables'));
      await tester.pumpAndSettle();
    }

    Finder maxHoursDropdown() => find.byWidgetPredicate(
        (w) => w is DropdownButton<int> && w.value != null);

    int currentMaxHours(WidgetTester tester) =>
        tester.widget<DropdownButton<int>>(maxHoursDropdown()).value!;

    testWidgets('a chip reads as off until it is tapped', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await generate(tester);

      expect(find.text('Less packed'), findsOneWidget);
      expect(find.text('Less packed — on'), findsNothing);
    });

    testWidgets('tapping applies the change and marks the chip on',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await generate(tester);
      final before = currentMaxHours(tester);

      await tester.tap(find.text('Less packed'));
      await tester.pumpAndSettle();

      expect(find.text('Less packed — on'), findsOneWidget);
      expect(currentMaxHours(tester), before - 1);
    });

    testWidgets('tapping again reverses the change and clears the chip',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await generate(tester);
      final before = currentMaxHours(tester);

      await tester.tap(find.text('Less packed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Less packed — on'));
      await tester.pumpAndSettle();

      expect(currentMaxHours(tester), before,
          reason: 'the second tap must restore the original value');
      expect(find.text('Less packed'), findsOneWidget);
      expect(find.text('Less packed — on'), findsNothing);
    });

    testWidgets('editing the same setting by hand releases the chip',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await generate(tester);

      await tester.tap(find.text('Less packed'));
      await tester.pumpAndSettle();
      expect(find.text('Less packed — on'), findsOneWidget);

      // Change max hours/day directly; the chip no longer set this value, so
      // it must stop claiming it did.
      await tester.tap(maxHoursDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('9').last);
      await tester.pumpAndSettle();

      expect(find.text('Less packed — on'), findsNothing);
      expect(find.text('Less packed'), findsOneWidget);
    });
  });

  group('results panel', () {
    testWidgets('shows the empty state before generating', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('No timetables generated yet'), findsOneWidget);
      expect(
        find.text('Select courses and click Generate to see results'),
        findsOneWidget,
      );
    });
  });
}
