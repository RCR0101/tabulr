import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/tabulr_down_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('TabulrDownScreen', () {
    testWidgets('shows the title and the provided message', (tester) async {
      await tester.pumpWidget(wrap(TabulrDownScreen(
        message: 'Down for scheduled maintenance.',
        onRetry: () async => false,
      )));

      expect(find.text('Tabulr is down'), findsOneWidget);
      expect(find.text('Down for scheduled maintenance.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('invokes onRetry when the button is tapped', (tester) async {
      var called = 0;
      await tester.pumpWidget(wrap(TabulrDownScreen(
        message: 'x',
        onRetry: () async {
          called++;
          return false;
        },
      )));

      await tester.tap(find.text('Try again'));
      await tester.pump(); // start async
      await tester.pumpAndSettle();

      expect(called, 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows a toast when retry reports still-down', (tester) async {
      await tester.pumpWidget(wrap(TabulrDownScreen(
        message: 'x',
        onRetry: () async => false,
      )));

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('Still down'), findsOneWidget);

      // Flush the toast's auto-dismiss timer/animation so no timers leak.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
