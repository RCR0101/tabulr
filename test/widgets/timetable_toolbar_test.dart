import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/common/first_that_fits.dart';
import 'package:timetable_maker/widgets/timetable_widget.dart';

void main() {
  final slots = [
    TimetableSlot(
      day: DayOfWeek.M,
      hours: const [2, 3],
      courseCode: 'CS F111',
      courseTitle: 'Computer Programming',
      sectionId: 'L1',
      instructor: 'Dr. A',
      room: '6101',
    ),
  ];

  /// Every action wired up — the widest the toolbar ever gets.
  Widget editorHarness({required double panelWidth}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: panelWidth,
              height: 700,
              child: TimetableWidget(
                timetableSlots: slots,
                availableCourses: const [],
                selectedSections: const [],
                onClear: () {},
                onRemoveSection: (_, __) {},
                onSave: () {},
                onAutoLoadCDCs: () {},
                onShowStats: () {},
                onUndo: () {},
                onRedo: () {},
                canUndo: true,
                canRedo: true,
                hasUnsavedChanges: true,
                onSizeChanged: (_) {},
                onLayoutChanged: (_) {},
              ),
            ),
          ),
        ),
      );

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size window,
    required double panelWidth,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(editorHarness(panelWidth: panelWidth));
  }

  /// Which candidate FirstThatFits actually laid out. Every candidate is built,
  /// so `find.text` matches variants that were never put on screen.
  int selectedVariant(WidgetTester tester) =>
      tester
          .renderObject<RenderFirstThatFits>(find.byType(FirstThatFits).first)
          .selectedIndex;

  /// Scopes a finder to the variant actually on screen.
  Finder onScreen(WidgetTester tester, Finder matching) => find.descendant(
        of: find.byKey(ValueKey('toolbar-variant-${selectedVariant(tester)}')),
        matching: matching,
      );

  group('toolbar fits its panel', () {
    // The editor gives the timetable Expanded(flex: 2) of the body, so a
    // 1440 px window leaves roughly 760 px — the width that overflowed.
    // No thresholds appear here on purpose: the widget measures its own
    // candidates, so these widths only have to span the plausible range.
    for (final panelWidth in <double>[
      1600, 1500, 1400, 1300, 1200, 1100, 1000, 900, 800, 760, 700, 620, 560,
      520, 460, 400, 360, 320, 300,
    ]) {
      testWidgets('no overflow at ${panelWidth.toInt()} px', (tester) async {
        await pumpAt(
          tester,
          window: const Size(1440, 900),
          panelWidth: panelWidth,
        );

        expect(tester.takeException(), isNull);
      });
    }

    for (final width in <double>[320, 360, 390, 430, 600]) {
      testWidgets('no overflow on a ${width.toInt()} px phone', (tester) async {
        await pumpAt(
          tester,
          window: Size(width, 780),
          panelWidth: width,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('progressive collapse', () {
    // Desktop candidates, widest first, as built by _buildDesktopAppBar:
    //   0 title + every action        3 compact chips
    //   1 no title                    4 icon-only Save
    //   2 actions folded into a menu  5 no undo/redo
    testWidgets('a wide panel shows the title and every action', (tester) async {
      await pumpAt(tester, window: const Size(1600, 900), panelWidth: 1500);

      expect(selectedVariant(tester), 0);
    });

    testWidgets('the title is the first thing dropped', (tester) async {
      await pumpAt(tester, window: const Size(1600, 900), panelWidth: 1100);

      expect(selectedVariant(tester), 1);
    });

    testWidgets('secondary actions fold into a menu next', (tester) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 760);

      expect(selectedVariant(tester), 2);
      expect(onScreen(tester, find.byIcon(Icons.more_vert)), findsOneWidget);
      // Save carries state worth seeing without opening a menu.
      expect(onScreen(tester, find.text('Save')), findsOneWidget);
      expect(onScreen(tester, find.text('Auto Load CDCs')), findsNothing);
    });

    testWidgets('collapsing further never hides a control outright',
        (tester) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 320);

      // The narrowest variant still keeps the view controls and the menu; only
      // undo/redo go, and those are in the command palette.
      expect(selectedVariant(tester), 5);
      expect(onScreen(tester, find.byIcon(Icons.more_vert)), findsOneWidget);
      expect(onScreen(tester, find.byIcon(Icons.view_module)), findsOneWidget);
    });

    testWidgets('the folded actions stay reachable from the menu',
        (tester) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 760);

      await tester.tap(onScreen(tester, find.byIcon(Icons.more_vert)));
      await tester.pumpAndSettle();

      // These labels exist only inside the popup, so one match proves the menu
      // opened carrying the actions that were folded away.
      expect(find.text('Clear Timetable'), findsOneWidget);
      expect(find.text('Auto Load CDCs'), findsWidgets);
    });

    testWidgets('the chosen variant widens again when the panel does',
        (tester) async {
      await pumpAt(tester, window: const Size(1600, 900), panelWidth: 700);
      expect(selectedVariant(tester), greaterThan(1));

      await tester.pumpWidget(editorHarness(panelWidth: 1500));
      expect(selectedVariant(tester), 0);
    });
  });
}
