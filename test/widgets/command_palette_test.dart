import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/command_palette.dart';

void main() {
  for (final size in [const Size(1200, 800), const Size(390, 844)]) {
    testWidgets('command palette is usable at ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => CommandPalette.show(
                    context,
                    onNavigate: (_) {},
                    currentScreen: null,
                    contextEntries: [
                      CommandPaletteEntry(
                        label: 'Unique Test Action',
                        subtitle: 'A context command used by this test',
                        icon: Icons.bolt_rounded,
                        category: CommandCategory.context,
                        onSelect: () => selections++,
                      ),
                    ],
                  ),
                  child: const Text('Open palette'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open palette'));
      await tester.pumpAndSettle();
      expect(find.text('Search Tabulr'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-palette-surface')),
        findsOneWidget,
      );
      expect(find.text('Ctrl K'), findsOneWidget);
      expect(find.text('Unique Test Action'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'unique test');
      await tester.pumpAndSettle();
      expect(find.text('Unique Test Action'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(selections, 1);
      expect(
        find.byKey(const ValueKey('command-palette-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty search explains how to recover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommandPalette(onNavigate: (_) {}, currentScreen: null),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz-no-command');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches "zzzz-no-command"'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
