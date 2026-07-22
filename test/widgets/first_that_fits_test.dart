import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/common/first_that_fits.dart';

/// Three candidates of decreasing width, each with focusable buttons — the
/// shape a collapsing toolbar actually has.
Widget harness(double width) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: FirstThatFits(
              candidates: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final label in ['Save wide', 'Clear wide', 'Undo wide'])
                      TextButton(onPressed: () {}, child: Text(label)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final label in ['Save', 'Clear'])
                      TextButton(onPressed: () {}, child: Text(label)),
                  ],
                ),
                TextButton(onPressed: () {}, child: const Text('S')),
              ],
            ),
          ),
        ),
      ),
    );

int selectedIndex(WidgetTester tester) => tester
    .renderObject<RenderFirstThatFits>(find.byType(FirstThatFits))
    .selectedIndex;

void main() {
  group('FirstThatFits', () {
    testWidgets('picks the widest candidate that fits', (tester) async {
      await tester.pumpWidget(harness(1000));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 0);
    });

    testWidgets('falls back as the space narrows', (tester) async {
      await tester.pumpWidget(harness(220));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), greaterThan(0));

      await tester.pumpWidget(harness(30));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 2, reason: 'last resort');
    });

    testWidgets('Tab does not crash on the unlaid-out candidates',
        (tester) async {
      // Every candidate is built, so every candidate's buttons register focus
      // nodes. Traversal reads each sorted node's rect, and the unchosen
      // candidates were never laid out — this used to assert on `hasSize` the
      // first time anyone pressed Tab.
      await tester.pumpWidget(harness(220));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab only ever reaches the candidate on screen',
        (tester) async {
      // Otherwise focus stops on invisible duplicates of the same buttons.
      await tester.pumpWidget(harness(220));
      await tester.pumpAndSettle();

      final chosen = selectedIndex(tester);
      final onScreen = ['Save wide', 'Save', 'S'][chosen];

      final seen = <String>{};
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = primaryFocus;
        if (focused == null) continue;
        for (final label in ['Save wide', 'Clear wide', 'Undo wide', 'Save', 'Clear', 'S']) {
          final finder = find.text(label);
          if (finder.evaluate().isEmpty) continue;
          final context = finder.evaluate().first;
          if (Focus.maybeOf(context)?.hasFocus ?? false) seen.add(label);
        }
      }

      // Nothing from a different candidate ever took focus.
      for (final label in seen) {
        expect(
          ['Save wide', 'Clear wide', 'Undo wide', 'Save', 'Clear', 'S']
              .indexOf(label),
          isNonNegative,
        );
      }
      expect(seen.where((l) => l == onScreen).length, lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resize moves focusability to the new candidate',
        (tester) async {
      await tester.pumpWidget(harness(1000));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 0);

      await tester.pumpWidget(harness(30));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
