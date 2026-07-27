import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/tutorial_service.dart';

/// The sidebar step spotlights a target that is both full height and flush
/// against the window origin, and tutorial_coach_mark mishandles each of those:
/// the content halo scales with the target's height, which threw the card off
/// the top of the viewport, and its painter skips drawing entirely for a target
/// at exactly `Offset.zero`, so the backdrop never dimmed. Together the page
/// looked untouched but only the sidebar responded to a tap — the reported
/// freeze, which "fixed itself" the moment the user clicked there.
///
/// Nothing dismisses the tour at the end: every exit path persists a flag
/// through the Firebase-backed settings service, which isn't available here.
/// The one test in this file finishes with the tree, and the singleton's
/// `_isShowing` dies with the process.
void main() {
  testWidgets('sidebar tour card lands inside the viewport', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext screenContext;
    await tester.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Builder(builder: (context) {
            screenContext = context;
            return Row(
              children: [
                // Stands in for AppSidebar: full height, fixed width, and — the
                // part that matters — flush against the window origin.
                SizedBox(
                  key: TutorialKeys.sidebarNav,
                  width: 280,
                  height: double.infinity,
                  child: const ColoredBox(color: Colors.grey),
                ),
                const Expanded(child: SizedBox()),
              ],
            );
          }),
        ),
      ),
    ));

    TutorialService().showTimetableListTutorial(screenContext, force: true);
    // Stepped by hand rather than pumpAndSettle: the overlay goes in on a
    // post-frame timer, and the card only renders once the focus animation has
    // ticked to completion and rebuilt.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final title = find.text('Everything lives here');
    expect(title, findsOneWidget);

    final card = tester.getRect(title);
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(screen.contains(card.topLeft), isTrue,
        reason: 'card top-left $card is outside the screen $screen');
    expect(screen.contains(card.bottomRight), isTrue,
        reason: 'card bottom-right $card is outside the screen $screen');
    // Beside the spotlighted sidebar, not on top of it.
    expect(card.left, greaterThanOrEqualTo(280));

    // And the backdrop is actually dimmed. The package's painter bails out on a
    // target at exactly Offset.zero, which left the page looking untouched
    // while the tour's overlay still swallowed every tap — the reported freeze.
    await tester.runAsync(() async {
      final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      // A point far from both the spotlight and the card: white page unless the
      // shadow is painted over it.
      const x = 1100, y = 700;
      final offset = (y * image.width + x) * 4;
      final red = data!.getUint8(offset);
      expect(red, lessThan(128),
          reason: 'backdrop at ($x, $y) is not dimmed (red=$red)');
    });
  });
}
