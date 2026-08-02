import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/guide_screen.dart';

import '../helpers/preview_harness.dart';

void main() {
  setUpAll(loadPreviewFont);

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render guide desktop - $name', (tester) async {
      usePreviewSurface(tester, const Size(2400, 3400));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: const GuideScreen(),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'guide_desktop_$name');
    });

    testWidgets('render guide phone - $name', (tester) async {
      usePreviewSurface(tester, const Size(820, 2600));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: const GuideScreen(initialAnchor: 'the-editor'),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'guide_phone_$name');
    });
  }
}
