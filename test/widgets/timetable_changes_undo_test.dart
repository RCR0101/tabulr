import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/admin/timetable_changes_review.dart';

void main() {
  testWidgets('earlier applies are listed, and only live ones can be undone', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TimetableChangesReview(noticeId: 'lms_hyd_10', preview: {
          'summary': '1 changes: 1 already in',
          'changes': [
            {'key': 'k', 'kind': 'instructor', 'course': 'CS F211', 'section': 'L1', 'status': 'done',
             'reason': '', 'before': 'New Prof', 'after': 'New Prof'},
          ],
          'applies': [
            {'id': 'a2', 'at': '2026-10-09T10:00:00Z', 'by': 'admin@x', 'count': 1,
             'courses': ['CS F211'], 'undone': false, 'undoable': true},
            {'id': 'a1', 'at': '2026-10-02T10:00:00Z', 'by': 'admin@x', 'count': 3,
             'courses': ['BIO F110', 'ME F212'], 'undone': true, 'undoable': false},
          ],
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Applied earlier'), findsOneWidget);
    expect(find.text('1 change: CS F211'), findsOneWidget);
    expect(find.text('3 changes: BIO F110, ME F212'), findsOneWidget);
    expect(find.text('admin@x · 2026-10-02 · undone'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Undo'), findsOneWidget);
  });
}
