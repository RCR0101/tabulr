import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/timetable_generator_widget.dart';
import '../helpers/test_data.dart';

final _courses = [
  makeCourse(courseCode: 'CS F111', courseTitle: 'Computer Programming'),
  makeCourse(courseCode: 'MATH F111', courseTitle: 'Mathematics I'),
];

Widget _host() => MaterialApp(
      home: Scaffold(
        body: TimetableGeneratorWidget(
          availableCourses: _courses,
          onTimetableSelected: (_) {},
        ),
      ),
    );

/// Every widget the framework rebuilt while [action] ran, as its debug line.
Future<List<String>> _rebuildsDuring(Future<void> Function() action) async {
  final lines = <String>[];
  final previousPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  debugPrintRebuildDirtyWidgets = true;
  try {
    await action();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previousPrint;
  }
  return lines;
}

/// Lines name widgets with their full description ("Building ListView(...)"),
/// so membership has to be a substring test, not list containment.
Matcher _rebuilt(String widgetName) => predicate<List<String>>(
      (lines) => lines.any((l) => l.contains('Building $widgetName')),
      'rebuilt a $widgetName',
    );

Future<void> _tapCheckbox(WidgetTester tester, String label) async {
  await tester.tap(find.ancestor(
    of: find.text(label),
    matching: find.byType(CheckboxListTile),
  ));
}

Future<void> _pickFirstCourse(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'CS F111');
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CS F111').last);
}

void main() {
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

  testWidgets('a constraint toggle does not rebuild the course search',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final rebuilt = await _rebuildsDuring(() async {
      await _tapCheckbox(tester, 'Minimize gaps between classes');
      await tester.pump();
    });

    // TypeAheadField is the expensive one on this screen — it carries an
    // overlay and its own text controller — and nothing about it depends on a
    // constraint checkbox.
    expect(rebuilt, isNot(_rebuilt('TypeAheadField')));
  });

  testWidgets('a constraint toggle does not rebuild the results panel',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final rebuilt = await _rebuildsDuring(() async {
      await _tapCheckbox(tester, 'Avoid back-to-back classes');
      await tester.pump();
    });

    // Asserting on ListView/GeneratedTimetableCard would be vacuous here —
    // nothing has been generated, so neither exists. The empty-state text is
    // the results panel's actual content in this state.
    expect(rebuilt, isNot(_rebuilt('Text("No timetables generated yet"')));
  });

  testWidgets('a constraint toggle still rebuilds its own panel',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final rebuilt = await _rebuildsDuring(() async {
      await _tapCheckbox(tester, 'Minimize gaps between classes');
      await tester.pump();
    });

    // The control against the tests above: the constraints panel MUST rebuild,
    // otherwise "nothing rebuilt" would pass them trivially.
    expect(rebuilt, _rebuilt('RangeSlider'));
  });

  testWidgets('picking a course does not rebuild the constraints panel',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final rebuilt = await _rebuildsDuring(() async {
      await _pickFirstCourse(tester);
      await tester.pump();
    });

    // RangeSlider belongs to the constraints panel; a course selection has
    // nothing to say to it.
    expect(rebuilt, isNot(_rebuilt('RangeSlider')));
  });

  testWidgets('the generate button enables once a mandatory course exists',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    FilledButton generateButton() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Generate Timetables'),
            matching: find.byType(FilledButton),
          ),
        );

    expect(generateButton().onPressed, isNull);

    await _pickFirstCourse(tester);
    await tester.pumpAndSettle();

    // The button subscribes to the course slice, so it saw the change without
    // the rest of the form being rebuilt.
    expect(generateButton().onPressed, isNotNull);
  });
}
