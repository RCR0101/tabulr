import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/guide_content.dart';
import 'package:timetable_maker/widgets/guide_visuals.dart';

import '../helpers/preview_harness.dart';

void main() {
  setUpAll(loadPreviewFont);

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('render guide visuals - $name', (tester) async {
      usePreviewSurface(tester, const Size(1500, 7000));

      await tester.pumpWidget(MaterialApp(
        theme: previewTheme(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final visual in GuideVisual.values)
                  GuideVisualFrame(visual: visual),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'guide_visuals_$name');
    });
  }
}
