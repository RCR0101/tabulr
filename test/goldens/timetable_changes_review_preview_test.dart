import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/admin/timetable_changes_review.dart';

import '../helpers/preview_harness.dart';

/// Renders the timetable-changes review with a row in every status, taken
/// from the real "Timetable changes-4/5" PDFs judged against live data. The
/// two snippets are changes.snippets() output for those rows.
void main() {
  setUpAll(loadPreviewFont);

  Map<String, dynamic> row(String key, String kind, String course, String section, String status,
          String before, String after, [String reason = '', String? snippet]) =>
      {'key': key, 'kind': kind, 'course': course, 'section': section, 'status': status,
       'before': before, 'after': after, 'reason': reason, 'snippet': snippet};
  String shot(String name) => base64Encode(File('test/fixtures/changes_snippet_$name.png').readAsBytesSync());
  final preview = {
    'summary': '7 changes: 3 to apply, 1 to check, 1 already in, 1 to add by hand, 1 not found',
    'changes': [
      row('a', 'instructor', 'CS F214', 'T3', 'apply', 'Sameera Muhamed Salam', 'Sameera Muhamed Salam, Arnab Hazra'),
      row('b', 'schedule', 'BIO F312', 'T1', 'apply', 'W 5 · G101', 'Th 1 · G101'),
      row('c', 'exam', 'CHEM F211', '', 'apply', 'Mid-sem: 10/10 MS2 · Compre: 05/12 AN', 'Mid-sem: 10/10 MS2 · Compre: 05/12 FN'),
      row('d', 'instructor', 'ME F341', 'P1', 'check', 'Mrinal Ketan Jagirdar', 'Sandip Shridharrao Deshmukh, Santanu Prasad Datta',
          "The live instructors differ from the PDF's existing list", shot('check')),
      row('e', 'exam', 'MGTS U102', '', 'done', 'Mid-sem: 08/10 MS1', 'Mid-sem: 08/10 MS1'),
      row('f', 'new_course', 'ECE F242', 'L1 T1', 'manual', '', 'L1 T1 · HARISH VIJAY DIXIT · M W 9 10 · I122',
          'Several sections share one hours cell; add it in Course Management', shot('manual')),
      row('g', 'schedule', 'BITS U437', 'L1', 'missing', '', '', 'BITS U437 is not in the timetable'),
    ],
  };

  for (final (name, brightness) in previewBrightnesses) {
    for (final (device, size) in [('phone', const Size(820, 2300)), ('desktop', const Size(1400, 1700))]) {
      testWidgets('render timetable changes review - $device $name', (tester) async {
        usePreviewSurface(tester, size);
        await tester.pumpWidget(MaterialApp(
          theme: previewTheme(brightness),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TimetableChangesReview(noticeId: 'x', preview: preview),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        // Image.memory decodes off the fake clock; wait for it, then repaint.
        await tester.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
        await tester.pumpAndSettle();
        expect(find.text('Apply 3'), findsOneWidget);
        // Open where a decision is needed (check, add by hand), closed elsewhere.
        expect(find.text('Hide the PDF'), findsNWidgets(2));
        await capturePreview(tester, 'timetable_changes_${device}_$name');
      });
    }
  }
}
