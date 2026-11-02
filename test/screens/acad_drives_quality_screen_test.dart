import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/admin/acad_drives_quality_screen.dart';
import 'package:timetable_maker/services/data/acad_drives_service.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    AcadDrivesService.firestoreForTest = db;
    AcadDrivesService.reviewerForTest = () => 'admin@hyderabad.bits-pilani.ac.in';
    await db.collection('acad_drives_files').doc('f1').set({
      'name': 'DBMS midsem.pdf', 'course_codes': ['CS F211'], 'resource_type': 'other', 'url': 'https://x',
    });
    await db.collection('acad_drives_files').doc('f2').set({
      'name': 'meme.png', 'course_codes': ['CS F211'], 'resource_type': 'other', 'url': 'https://y',
    });
    Future<void> report(String id, String fileId, String problem, Map<String, dynamic> extra, int minute) =>
        db.collection('acad_drives_reports').doc(id).set({
          'fileId': fileId, 'fileName': fileId == 'f1' ? 'DBMS midsem.pdf' : 'meme.png',
          'currentCourse': 'CS F211', 'currentType': 'other', 'problem': problem,
          'reportedBy': 's@hyderabad.bits-pilani.ac.in', 'status': 'open',
          'reportedAt': Timestamp.fromDate(DateTime(2026, 10, 1, 9, minute)), ...extra,
        });
    await report('r1', 'f1', 'wrong_course', {'suggestedCourse': 'CS F212', 'note': 'this is DBMS'}, 1);
    await report('r2', 'f2', 'not_academic', {}, 2);
    await db.collection('acad_drives_requests').doc('CS_F212__pyq__aH').set(
        {'course': 'CS F212', 'type': 'pyq', 'requestedBy': 'a@x', 'note': '2024 compre'});
    await db.collection('acad_drives_requests').doc('CS_F212__pyq__bH').set(
        {'course': 'CS F212', 'type': 'pyq', 'requestedBy': 'b@x'});
  });

  tearDown(() {
    AcadDrivesService.firestoreForTest = null;
    AcadDrivesService.reviewerForTest = null;
  });

  Widget app() => MaterialApp(
        home: AcadDrivesQualityScreen(
          loadCourses: () async => [
            {'course_code': 'CS F211', 'title': 'Data Structures'},
            {'course_code': 'CS F212', 'title': 'DBMS'},
          ],
          loadIndex: () async => [
            {'code': 'CS F211', 'fileCount': 2, 'typeCounts': {'other': 2}},
            {'code': 'CS F212', 'fileCount': 3, 'typeCounts': {'notes': 3}},
          ],
          pickCourse: (_) async => 'CS F213',
        ),
      );

  testWidgets('a report is fixed in one tap: the file moves and the report closes', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Filed under the wrong course'), findsOneWidget);
    expect(find.text('"this is DBMS"'), findsOneWidget);
    await tester.tap(find.text('Move to CS F212'));
    await tester.pumpAndSettle();

    final f1 = (await db.collection('acad_drives_files').doc('f1').get()).data()!;
    expect(f1['course_codes'], ['CS F212']);
    expect(f1['manual_course'], isTrue);
    final r1 = (await db.collection('acad_drives_reports').doc('r1').get()).data()!;
    expect(r1['status'], 'fixed');
    expect(r1['resolution'], 'moved to CS F212');
    expect(r1['reviewedBy'], 'admin@hyderabad.bits-pilani.ac.in');
    expect(find.text('Move to CS F212'), findsNothing);

    await tester.tap(find.text('Hide file'));
    await tester.pumpAndSettle();
    expect((await db.collection('acad_drives_files').doc('f2').get()).data()!['hidden'], isTrue);
    expect(find.text('No open reports'), findsOneWidget);
    // Let the confirmation toast time out.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('coverage ranks asked-for courses and clears them', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coverage'));
    await tester.pumpAndSettle();

    expect(find.text('CS F212 · DBMS'), findsOneWidget);
    expect(find.text('2 students asked: past papers ×2'), findsOneWidget);
    expect(find.text('"2024 compre"'), findsOneWidget);
    // CS F211 has files but no past papers: still a gap.
    expect(find.text('CS F211 · Data Structures'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    // The confirm dialog's button.
    await tester.tap(find.text('Clear').last);
    await tester.pumpAndSettle();
    expect((await db.collection('acad_drives_requests').get()).docs, isEmpty);
    expect(find.textContaining('students asked'), findsNothing);
  });
}
