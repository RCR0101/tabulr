import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/admin/data_freshness_panel.dart';

import '../helpers/preview_harness.dart';

/// Renders the admin data-freshness panel with every state on show.
void main() {
  setUpAll(loadPreviewFont);

  final now = DateTime.now();
  final thisTerm = now.subtract(const Duration(days: 10));
  final lastTerm = now.subtract(const Duration(days: 200));
  final rows = [
    FreshnessRow('Timetable', {'hyderabad': thisTerm, 'pilani': thisTerm, 'goa': lastTerm},
        howTo: 'Timetable Upload below'),
    FreshnessRow('Academic calendar', {'hyderabad': thisTerm, 'pilani': null, 'goa': null},
        howTo: 'Rides along with the timetable PDF'),
    FreshnessRow('Exam seating', {'hyderabad': lastTerm},
        howTo: 'From the LMS: Apply it under Upstream changes'),
    FreshnessRow('Prerequisites', {null: lastTerm}, howTo: 'scripts/upload-prerequisites.js'),
    FreshnessRow('Acad Drives', {null: thisTerm}, howTo: 'Weekly sync, Monday mornings'),
  ];

  for (final (name, brightness) in previewBrightnesses) {
    for (final (device, size) in [('phone', const Size(820, 1500)), ('desktop', const Size(2000, 900))]) {
      testWidgets('render data freshness - $device $name', (tester) async {
        usePreviewSurface(tester, size);
        await tester.pumpWidget(MaterialApp(
          theme: previewTheme(brightness),
          home: Scaffold(body: SingleChildScrollView(child: DataFreshnessPanel(rows: rows))),
        ));
        await tester.pumpAndSettle();
        await capturePreview(tester, 'data_freshness_${device}_$name');
      });
    }
  }
}
