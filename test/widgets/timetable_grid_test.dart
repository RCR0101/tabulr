import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_display.dart';
import 'package:timetable_maker/widgets/timetable/course_palette.dart';
import 'package:timetable_maker/widgets/timetable/timetable_agenda.dart';
import 'package:timetable_maker/widgets/timetable/timetable_grid.dart';

void main() {
  TimetableSlot slot({
    required DayOfWeek day,
    required List<int> hours,
    String code = 'CS F111',
    String section = 'L1',
    String title = 'Computer Programming',
    String room = '6101',
  }) =>
      TimetableSlot(
        day: day,
        hours: hours,
        courseCode: code,
        courseTitle: title,
        sectionId: section,
        instructor: 'Dr. A',
        room: room,
      );

  /// A realistic week: every day busy and classes running to 5 PM, so the grid
  /// is not cropped down to a couple of rows.
  List<TimetableSlot> fullWeek() => [
        for (final (i, day) in DayOfWeek.values.indexed)
          slot(
            day: day,
            hours: [2 + i],
            code: 'CS F11$i',
            section: 'L$i',
          ),
        slot(day: DayOfWeek.M, hours: [10], code: 'PHY F110', section: 'P1'),
      ];

  /// The grid as the editor lays it out: a fixed panel inside the window.
  /// [panel] mirrors `Expanded(flex: 2)` of a desktop body.
  Widget harness(
    List<TimetableSlot> slots, {
    TimetableSize size = TimetableSize.medium,
    TimetableLayout layout = TimetableLayout.vertical,
    Size panel = const Size(760, 700),
    bool showAllHours = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: panel.width,
            height: panel.height,
            child: Builder(
              builder: (context) => TimetableGrid(
                slots: slots,
                layout: layout,
                size: size,
                showAllHours: showAllHours,
                palette: CoursePalette.forCourses(
                  context,
                  slots.map((s) => s.courseCode),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A desktop-sized window, so the grid does not take its touch code paths.
  /// Also unmounts the tree, which cancels the current-time ticker.
  Future<void> pumpDesktop(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(widget);
  }

  Finder horizontalScrollViews() => find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );

  group('merged blocks', () {
    testWidgets('a three-hour lab renders one card, not three', (tester) async {
      await pumpDesktop(
        tester,
        harness([slot(day: DayOfWeek.M, hours: [2, 3, 4])]),
      );

      // The old grid painted one full cell per hour, repeating the code,
      // title, instructor and room three times over.
      expect(find.text('CS F111'), findsOneWidget);
      expect(find.byKey(const ValueKey('block-CS F111-L1-2')), findsOneWidget);
    });

    testWidgets('a merged block spans the height of its hours', (tester) async {
      await pumpDesktop(
        tester,
        harness([
          slot(day: DayOfWeek.M, hours: [2, 3, 4]),
          slot(day: DayOfWeek.T, hours: [2], code: 'MATH F112', section: 'L2'),
        ]),
      );

      final threeHour =
          tester.getSize(find.byKey(const ValueKey('block-CS F111-L1-2')));
      final oneHour =
          tester.getSize(find.byKey(const ValueKey('block-MATH F112-L2-2')));

      expect(threeHour.height, closeTo(oneHour.height * 3, 0.01));
    });

    testWidgets('two separate meetings of one section stay separate cards',
        (tester) async {
      await pumpDesktop(
        tester,
        harness([slot(day: DayOfWeek.M, hours: [2, 7])]),
      );

      expect(find.byKey(const ValueKey('block-CS F111-L1-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('block-CS F111-L1-7')), findsOneWidget);
    });
  });

  group('fitting the viewport', () {
    testWidgets('never scrolls sideways at a desktop panel width',
        (tester) async {
      await pumpDesktop(
        tester,
        harness([
          slot(day: DayOfWeek.M, hours: [2]),
          slot(day: DayOfWeek.W, hours: [5], code: 'MATH F112'),
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(horizontalScrollViews(), findsNothing);
      expect(
        tester.getSize(find.byType(TimetableGrid)).width,
        lessThanOrEqualTo(760.0),
      );
    });

    testWidgets('fit density puts the whole grid on screen at once',
        (tester) async {
      await pumpDesktop(
        tester,
        harness(
          [slot(day: DayOfWeek.M, hours: [2, 3])],
          size: TimetableSize.fit,
        ),
      );

      // Nothing left to scroll to on either axis — the point of the mode.
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, 0.0);
      expect(horizontalScrollViews(), findsNothing);
    });

    testWidgets('fit still fits with all twelve hours and Saturday shown',
        (tester) async {
      await pumpDesktop(
        tester,
        harness(
          [slot(day: DayOfWeek.M, hours: [2])],
          size: TimetableSize.fit,
          showAllHours: true,
        ),
      );

      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, 0.0);
    });

    testWidgets('a fixed density scrolls vertically rather than shrinking',
        (tester) async {
      await pumpDesktop(
        tester,
        harness(fullWeek(), size: TimetableSize.extraLarge),
      );

      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.maxScrollExtent, greaterThan(0.0));
    });

    testWidgets('falls back to horizontal scrolling on a phone-width panel',
        (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      await tester.pumpWidget(harness(fullWeek(), panel: const Size(382, 700)));

      // Six 84 px columns do not fit 382 px, so the grid scrolls — but it
      // scrolls at a legible size instead of being zoomed out to 46 px columns.
      expect(horizontalScrollViews(), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('pinned headers', () {
    testWidgets('day names stay put while the body scrolls', (tester) async {
      await pumpDesktop(
        tester,
        harness(fullWeek(), size: TimetableSize.extraLarge),
      );

      final before = tester.getTopLeft(find.text('Monday'));
      await tester.drag(find.byType(TimetableGrid), const Offset(0, -200));
      await tester.pump();
      final after = tester.getTopLeft(find.text('Monday'));

      expect(after, before);
    });

    testWidgets('the hour gutter stays put while the body scrolls sideways',
        (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      await tester.pumpWidget(harness(fullWeek(), panel: const Size(382, 700)));

      final before = tester.getTopLeft(find.text('8AM'));
      await tester.drag(horizontalScrollViews().first, const Offset(-120, 0));
      await tester.pump();

      expect(tester.getTopLeft(find.text('8AM')), before);
    });
  });

  group('content adapts to the space available', () {
    testWidgets('a one-hour block at medium density carries the instructor',
        (tester) async {
      // Four lines need roughly 70 px of content box and a medium row leaves
      // about 72, so the instructor fits without a two-hour block.
      await pumpDesktop(
        tester,
        harness(fullWeek(), size: TimetableSize.medium),
      );

      expect(find.text('Dr. A'), findsWidgets);
      expect(find.text('Computer Programming'), findsWidgets);
    });

    testWidgets('a compact one-hour block drops the instructor first',
        (tester) async {
      await pumpDesktop(
        tester,
        harness(fullWeek(), size: TimetableSize.compact),
      );

      expect(find.text('CS F110'), findsOneWidget);
      // The title survives; who teaches it is the first thing to go.
      expect(find.text('Dr. A'), findsNothing);
    });

    testWidgets('nothing overflows at any density', (tester) async {
      for (final size in TimetableSize.values) {
        await pumpDesktop(tester, harness(fullWeek(), size: size));
        expect(tester.takeException(), isNull, reason: size.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('nothing overflows in a narrow column', (tester) async {
      await pumpDesktop(
        tester,
        harness(fullWeek(), panel: const Size(420, 700)),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('colour assignment', () {
    testWidgets('distinct courses get distinct accents', (tester) async {
      late CoursePalette palette;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = CoursePalette.forCourses(context, const [
                'CS F111',
                'MATH F112',
                'PHY F110',
                'BITS F110',
                'CHEM F110',
                'EEE F111',
              ]);
              return const SizedBox();
            },
          ),
        ),
      );

      final colors = [
        'CS F111',
        'MATH F112',
        'PHY F110',
        'BITS F110',
        'CHEM F110',
        'EEE F111',
      ].map(palette.colorFor).toSet();

      // Hashing the course code collided often enough that two courses sharing
      // a colour was the common case, not the exception.
      expect(colors, hasLength(6));
    });

    testWidgets('a course keeps its accent when another is added',
        (tester) async {
      late CoursePalette before;
      late CoursePalette after;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              before = CoursePalette.forCourses(context, const ['CS F111']);
              after = CoursePalette.forCourses(
                context,
                const ['CS F111', 'MATH F112'],
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(after.colorFor('CS F111'), before.colorFor('CS F111'));
    });
  });

  group('export', () {
    /// Reproduces exportToPNG's overlay entry: an off-screen Positioned with
    /// only left/top, so both axes are unbounded and the tree must size to
    /// content.
    Future<void> pumpExport(
      WidgetTester tester,
      List<TimetableSlot> slots, {
      TimetableSize size = TimetableSize.extraLarge,
      Set<TimetableField>? fields,
    }) async {
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Material(
                  child: UnconstrainedBox(
                    child: Builder(
                      builder: (context) => TimetableGrid(
                        slots: slots,
                        layout: TimetableLayout.vertical,
                        size: size,
                        isForExport: true,
                        visibleFields: fields ?? TimetableField.values.toSet(),
                        palette: CoursePalette.forCourses(
                          context,
                          slots.map((s) => s.courseCode),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('sizes to content instead of overflowing or scrolling',
        (tester) async {
      await pumpExport(tester, fullWeek());

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
    });

    testWidgets('a short week exports narrow rather than stretched',
        (tester) async {
      // Filling a fixed 2000 px capture box would give this three columns of
      // roughly 600 px each; cards must keep their shape.
      await pumpExport(tester, [
        slot(day: DayOfWeek.M, hours: [2]),
        slot(day: DayOfWeek.W, hours: [3], code: 'MATH F112', section: 'L2'),
      ]);

      final threeDay = tester.getSize(find.byType(TimetableGrid)).width;

      await tester.pumpWidget(const SizedBox());
      await pumpExport(tester, fullWeek());
      final sixDay = tester.getSize(find.byType(TimetableGrid)).width;

      expect(threeDay, lessThan(sixDay));
      // Column width is the same in both; only the count differs.
      expect(sixDay - threeDay, closeTo(264 * 3, 1.0));
    });

    testWidgets('keeps card geometry independent of how many days there are',
        (tester) async {
      await pumpExport(tester, [slot(day: DayOfWeek.M, hours: [2])]);
      final narrow = tester.getSize(find.byKey(const ValueKey('block-CS F111-L1-2')));

      await tester.pumpWidget(const SizedBox());
      await pumpExport(tester, fullWeek());
      final wide = tester.getSize(find.byKey(const ValueKey('block-CS F110-L0-2')));

      expect(narrow.width, closeTo(wide.width, 0.01));
      expect(narrow.height, closeTo(wide.height, 0.01));
    });

    testWidgets('crops trailing days and hours, as the screen does',
        (tester) async {
      await pumpExport(tester, [
        slot(day: DayOfWeek.M, hours: [2]),
        slot(day: DayOfWeek.W, hours: [3], code: 'MATH F112', section: 'L2'),
      ]);

      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Saturday'), findsNothing);
      expect(find.text('10AM'), findsOneWidget);
      expect(find.text('7PM'), findsNothing);
    });

    testWidgets('honours the export field options', (tester) async {
      await pumpExport(
        tester,
        fullWeek(),
        fields: const {TimetableField.courseCode, TimetableField.room},
      );

      expect(find.text('CS F110'), findsOneWidget);
      expect(find.text('6101'), findsWidgets);
      expect(find.text('Computer Programming'), findsNothing);
      expect(find.text('Dr. A'), findsNothing);
    });

    testWidgets('leaves out the today tint and the current-time line',
        (tester) async {
      // Both would be baked into a shared PNG and stale the moment it is sent.
      await pumpExport(tester, fullWeek());

      final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(painters, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('agenda', () {
    testWidgets('lists each meeting once under its day', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TimetableAgenda(
                slots: [
                  slot(day: DayOfWeek.M, hours: [2, 3]),
                  slot(day: DayOfWeek.W, hours: [5], code: 'MATH F112'),
                ],
                palette: CoursePalette.forCourses(
                  context,
                  const ['CS F111', 'MATH F112'],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('CS F111'), findsOneWidget);
      expect(find.text('1 class'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an empty state rather than a blank pane', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TimetableAgenda(
                slots: const [],
                palette: CoursePalette.forCourses(context, const []),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('No classes yet'), findsOneWidget);
    });
  });
}
