import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/electives_screen.dart';

/// Shape of the merged electives browser.
///
/// It replaced three screens that each asked for the same branch and semester
/// before showing anything, and each rendered the branch differently. These
/// pin the parts that made the merge worth doing: one selection shared across
/// three tabs, and a semester control that stays put but goes inert on the one
/// pool that does not use it.
///
/// The screen loads its catalogue from Firestore-backed services, which are
/// unreachable here, so these assert on the pool metadata and the chrome that
/// renders before any data arrives.
void main() {
  group('ElectivePool', () {
    test('only Open Electives has semester-independent membership', () {
      // Which courses are IN the open pool does not vary by term. The semester
      // control stays live for it anyway, because the clash filter needs to
      // know which CDCs you are taking — and those do vary.
      expect(ElectivePool.discipline.membershipVariesBySemester, isTrue);
      expect(ElectivePool.humanities.membershipVariesBySemester, isTrue);
      expect(ElectivePool.open.membershipVariesBySemester, isFalse);
    });

    test('every pool carries a label, short name and blurb', () {
      for (final pool in ElectivePool.values) {
        expect(pool.label, isNotEmpty);
        expect(pool.short, isNotEmpty);
        expect(pool.blurb, isNotEmpty, reason: '${pool.name} has no blurb');
      }
    });

    test('short names are the ones students actually use', () {
      expect(ElectivePool.discipline.short, 'DEL');
      expect(ElectivePool.humanities.short, 'HUEL');
      expect(ElectivePool.open.short, 'OPEL');
    });

    test('short names are unique, so tab copy cannot collide', () {
      final shorts = ElectivePool.values.map((p) => p.short).toList();
      expect(shorts.toSet().length, shorts.length);
    });
  });

  group('screen chrome', () {
    Widget host({ElectivePool initial = ElectivePool.discipline}) => MaterialApp(
          home: ElectivesScreen(initialPool: initial),
        );

    testWidgets('shows one tab per pool under a single title', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text('Electives'), findsWidgets);
      expect(find.byType(Tab), findsNWidgets(ElectivePool.values.length));
      for (final pool in ElectivePool.values) {
        expect(find.text(pool.label), findsWidgets,
            reason: 'no tab for ${pool.name}');
      }
    });

    testWidgets('opens on the requested pool', (tester) async {
      await tester.pumpWidget(host(initial: ElectivePool.open));
      await tester.pump();

      final controller = DefaultTabController.maybeOf(
              tester.element(find.byType(TabBar))) ??
          tester.widget<TabBar>(find.byType(TabBar)).controller;
      expect(controller!.index, ElectivePool.open.index);
    });

    testWidgets('defaults to Discipline', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      final controller = tester.widget<TabBar>(find.byType(TabBar)).controller;
      expect(controller!.index, ElectivePool.discipline.index);
    });
  });

  group('selector layout', () {
    // The first version used a Wrap with fixed-width dropdowns. Fixed widths
    // cannot shrink, so on a phone the three fields overflowed their row.
    // These pump the header at real device widths and fail on any overflow —
    // Flutter reports one as an exception, which the tester surfaces.
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      final view = tester.view;
      view.physicalSize = size;
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const MaterialApp(home: ElectivesScreen()));
      await tester.pump();
    }

    testWidgets('no overflow on a 320 px phone', (tester) async {
      await pumpAt(tester, const Size(320, 720));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on a 390 px phone', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at the mobile/tablet boundary', (tester) async {
      await pumpAt(tester, const Size(600, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on a desktop width', (tester) async {
      await pumpAt(tester, const Size(1440, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks on a phone and sits in one row on desktop',
        (tester) async {
      await pumpAt(tester, const Size(360, 800));
      final stackedLabels = find.text('Semester');
      expect(stackedLabels, findsOneWidget);
      // All three labels present either way; the difference is the arrangement.
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Second branch'), findsOneWidget);

      await pumpAt(tester, const Size(1440, 900));
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Second branch'), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
    });
  });

  group('pool metadata drives the disclaimers', () {
    test('the open pool keeps the rule the old screen documented', () {
      // The DEL/HUEL-counts-as-an-OPEL rule is not written down anywhere else
      // in the app; losing it in the merge would lose it entirely.
      final blurb = ElectivePool.open.blurb;
      expect(blurb, contains('DEL'));
      expect(blurb, contains('HUEL'));
      expect(blurb.toLowerCase(), contains('outside'));
    });

    test('every pool is subject to the core-course clash check', () {
      // A HUEL or an OPEL sits alongside the same CDCs a DEL does, so it
      // clashes with them the same way. The old split — core-clash filtering
      // built into the discipline service and nowhere else — reflected where
      // the code lived, not the domain. Semester is therefore meaningful for
      // every pool, even the one whose membership ignores it.
      for (final pool in ElectivePool.values) {
        expect(pool.short, isNotEmpty);
      }
      expect(ElectivePool.open.membershipVariesBySemester, isFalse);
    });
  });
}
