import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/route_utils.dart';

/// A pushed route standing in for the timetable editor: optionally guarded by
/// an unsaved-changes prompt, with a button that calls [popThen].
class _GuardedPage extends StatelessWidget {
  final bool guarded;
  final VoidCallback onLeft;

  const _GuardedPage({required this.guarded, required this.onLeft});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !guarded,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: const Text('Unsaved changes'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (leave == true && navigator.canPop()) navigator.pop();
      },
      child: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => popThen(context, onLeft),
            child: const Text('Go elsewhere'),
          ),
        ),
      ),
    );
  }
}

Future<void> pumpAndPush(
  WidgetTester tester, {
  required bool guarded,
  required VoidCallback onLeft,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => _GuardedPage(guarded: guarded, onLeft: onLeft),
            ),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  group('popThen', () {
    testWidgets('runs the callback once an unguarded route pops',
        (tester) async {
      var left = false;
      await pumpAndPush(tester, guarded: false, onLeft: () => left = true);

      await tester.tap(find.text('Go elsewhere'));
      await tester.pumpAndSettle();

      expect(left, isTrue);
      expect(find.text('Open editor'), findsOneWidget);
    });

    testWidgets('does not run the callback while the guard is still asking',
        (tester) async {
      var left = false;
      await pumpAndPush(tester, guarded: true, onLeft: () => left = true);

      await tester.tap(find.text('Go elsewhere'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(left, isFalse);
    });

    testWidgets('never runs the callback when the user backs out',
        (tester) async {
      // The whole point of deferring: a cancelled prompt must leave the app
      // exactly where it was, not on the screen they didn't go to.
      var left = false;
      await pumpAndPush(tester, guarded: true, onLeft: () => left = true);

      await tester.tap(find.text('Go elsewhere'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();

      expect(left, isFalse);
      expect(find.text('Go elsewhere'), findsOneWidget);
    });

    testWidgets('runs the callback once the user confirms leaving',
        (tester) async {
      var left = false;
      await pumpAndPush(tester, guarded: true, onLeft: () => left = true);

      await tester.tap(find.text('Go elsewhere'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(left, isTrue);
      expect(find.text('Open editor'), findsOneWidget);
    });

    testWidgets('is inert on the root route, which has nothing to pop to',
        (tester) async {
      var left = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => popThen(context, () => left = true),
              child: const Text('Go elsewhere'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Go elsewhere'));
      await tester.pumpAndSettle();

      expect(left, isFalse);
      expect(find.text('Go elsewhere'), findsOneWidget);
    });
  });
}
