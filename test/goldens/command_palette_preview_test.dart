import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/command_palette.dart';

import '../helpers/preview_harness.dart';

void main() {
  setUpAll(loadPreviewFont);

  for (final size in [const Size(2400, 1500), const Size(780, 1688)]) {
    testWidgets(
      'command palette ${size.width > 1000 ? 'desktop' : 'mobile'} preview',
      (tester) async {
        usePreviewSurface(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: previewTheme(Brightness.light),
            home: RepaintBoundary(
              child: Builder(
                builder:
                    (context) => Scaffold(
                      appBar: AppBar(title: const Text('Timetables')),
                      body: Center(
                        child: FilledButton.icon(
                          onPressed:
                              () => CommandPalette.show(
                                context,
                                onNavigate: (_) {},
                                currentScreen: null,
                                onToggleTheme: () {},
                                contextEntries: [
                                  CommandPaletteEntry(
                                    label: 'Create a timetable',
                                    subtitle: 'Start a new semester plan',
                                    icon: Icons.add_rounded,
                                    category: CommandCategory.context,
                                    onSelect: () {},
                                  ),
                                ],
                              ),
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Search Tabulr'),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Search Tabulr'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          'command_palette_${size.width > 1000 ? 'desktop' : 'mobile'}',
          boundaryFinder: find.byKey(
            const ValueKey('command-palette-route-boundary'),
          ),
        );
      },
    );
  }
}
