import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
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

  Widget editorHarness({
    required double panelWidth,
    bool showBasisToggle = false,
    CreditBasis creditBasis = CreditBasis.units,
  }) => MaterialApp(
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

  group('compact control strip', () {
    for (final panelWidth in <double>[
      1600,
      1200,
      980,
      760,
      560,
      400,
      320,
      300,
    ]) {
      testWidgets('has no overflow at ${panelWidth.toInt()} px', (
        tester,
      ) async {
        await pumpAt(
          tester,
          window: const Size(1440, 900),
          panelWidth: panelWidth,
        );

        expect(tester.takeException(), isNull);
      });
    }

    for (final width in <double>[320, 360, 390, 430, 600]) {
      testWidgets('has no overflow on a ${width.toInt()} px phone', (
        tester,
      ) async {
        await pumpAt(tester, window: Size(width, 780), panelWidth: width);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide strips use their available space', (tester) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 1200);

      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Auto Load CDCs'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    });

    testWidgets(
      'keeps primary controls visible and secondary actions grouped',
      (tester) async {
        await pumpAt(tester, window: const Size(1440, 900), panelWidth: 760);

        expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
        expect(find.byIcon(Icons.redo_rounded), findsOneWidget);
        expect(find.byIcon(Icons.fit_screen), findsOneWidget);
        expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
        expect(find.text('Auto Load CDCs'), findsNothing);
        expect(find.byTooltip('Save timetable'), findsOneWidget);
      },
    );

    testWidgets('secondary actions stay reachable from one menu', (
      tester,
    ) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 760);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Auto Load CDCs'), findsOneWidget);
      expect(find.text('Timetable stats'), findsOneWidget);
      expect(find.text('Clear timetable'), findsOneWidget);
    });

    testWidgets('narrow strips scroll instead of dropping controls', (
      tester,
    ) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 320);

      final horizontalScrolls = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(horizontalScrolls, isNotEmpty);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });
  });

  group('block details', () {
    testWidgets('desktop opens an inspector without covering the timetable', (
      tester,
    ) async {
      await pumpAt(tester, window: const Size(1440, 900), panelWidth: 1100);

      await tester.tap(find.text('CS F111').first);
      await tester.pumpAndSettle();

      expect(find.text('Remove section'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byTooltip('Close details'), findsOneWidget);
    });

    testWidgets('mobile uses a bottom sheet for the same details', (
      tester,
    ) async {
      await pumpAt(tester, window: const Size(390, 780), panelWidth: 390);

      await tester.tap(find.text('CS F111').first);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Remove section'), findsOneWidget);
    });
  });

  group('credit basis toggle', () {
    testWidgets('each option explains itself, not the current selection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      for (final basis in CreditBasis.values) {
        await tester.pumpWidget(
          editorHarness(
            panelWidth: 1500,
            showBasisToggle: true,
            creditBasis: basis,
          ),
        );

        final messages =
            tester
                .widgetList<Tooltip>(find.byType(Tooltip))
                .map((t) => t.message)
                .toList();
        expect(messages, contains('Credits — 2025 batch and earlier'));
        expect(messages, contains('Credit hours — 2026 batch onwards'));
      }
    });
  });
}
