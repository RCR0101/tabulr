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
  Widget editorHarness({
    required double panelWidth,
    bool showBasisToggle = false,
    CreditBasis creditBasis = CreditBasis.units,
  }) =>
      MaterialApp(
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
                creditBasis: creditBasis,
                onCreditBasisChanged: showBasisToggle ? (_) {} : null,
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
    //   0 title + every action           4 actions folded into a menu
    //   1 no title                       5 + icon-only Save
    //   2 compact chips, actions kept    6 no undo/redo
    //   3 + icon-only Save
    //
    // 2 and 3 exist so a laptop-width window shrinks the chips before it hides
    // three actions behind the overflow menu.
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

      expect(selectedVariant(tester), 4);
      expect(onScreen(tester, find.byIcon(Icons.more_vert)), findsOneWidget);
      // Save carries state worth seeing without opening a menu.
      expect(onScreen(tester, find.text('Save')), findsOneWidget);
      expect(onScreen(tester, find.text('Auto Load CDCs')), findsNothing);
    });

    testWidgets('a laptop width shrinks the chips before hiding actions',
        (tester) async {
      // The regression this pins: `expandActions: false` used to be tried
      // before the compact chips, so this width lost Auto Load CDCs, Quick
      // Replace and Stats while the chips still carried their full labels.
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 980);

      expect(selectedVariant(tester), lessThan(4),
          reason: 'actions were folded away before the chips were shrunk');
      expect(onScreen(tester, find.text('Auto Load CDCs')), findsOneWidget);
    });

    testWidgets('collapsing further never hides a control outright',
        (tester) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 320);

      // The narrowest variant still keeps the view controls and the menu; only
      // undo/redo go, and those are in the command palette.
      expect(selectedVariant(tester), 6);
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

  group('credit basis toggle', () {
    /// Each segment carries its own tooltip.
    ///
    /// One Tooltip around the whole control described the CURRENT selection
    /// wherever the pointer went, so hovering "Credit hours" while counting in
    /// credits explained credits — the opposite of what hovering asks.
    testWidgets('each option explains itself, not the current selection',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      for (final basis in CreditBasis.values) {
        await tester.pumpWidget(editorHarness(
          panelWidth: 1500,
          showBasisToggle: true,
          creditBasis: basis,
        ));

        // Both messages are present whichever side is selected, so the one the
        // pointer lands on is the one that answers.
        final messages = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((t) => t.message)
            .toList();
        expect(messages, contains('Credits — 2025 batch and earlier'),
            reason: 'selected: $basis');
        expect(messages, contains('Credit hours — 2026 batch onwards'),
            reason: 'selected: $basis');
      }
    });
  });
}
