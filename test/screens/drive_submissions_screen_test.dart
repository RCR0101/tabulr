import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/admin/drive_submissions_screen.dart';
import 'package:timetable_maker/services/data/acad_drives_service.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    AcadDrivesService.firestoreForTest = db;
    Future<void> submit(String id, String title, String link, int minute) =>
        db.collection('acad_drives_submissions').doc(id).set({
          'title': title,
          'driveLink': link,
          'contributorName': 'A',
          'submittedBy': 'a@hyderabad.bits-pilani.ac.in',
          'status': 'pending',
          'submittedAt': Timestamp.fromDate(DateTime(2026, 10, 1, 9, minute)),
        });
    await submit('s1', 'Fresh drive', 'https://drive.google.com/drive/folders/NEW1?usp=sharing', 1);
    await submit('s2', 'Same again', 'https://drive.google.com/drive/folders/NEW1?usp=drive_link', 2);
    await submit('s3', 'Old drive', 'https://drive.google.com/drive/folders/OLD9', 3);
    await submit('s4', 'Not drive', 'https://onedrive.live.com/x', 4);
    await db.collection('acad_drives_sources').doc('DSA PYQs').set({
      'name': 'DSA PYQs',
      'driveLink': 'https://drive.google.com/drive/folders/OLD9',
      'contributor': 'B',
    });
    await db.collection('acad_drives_sources').doc('Locked').set({
      'name': 'Locked',
      'driveLink': 'https://drive.google.com/drive/folders/L0CK',
      'contributor': 'C',
      'lastSync': {'problem': 'Tabulr cannot open this link.', 'processed': 0},
    });
    await db.collection('acad_drives_sources').doc('Healthy').set({
      'name': 'Healthy',
      'driveLink': 'https://drive.google.com/drive/folders/OK',
      'lastSync': {'problem': null, 'processed': 12},
    });
  });

  tearDown(() => AcadDrivesService.firestoreForTest = null);

  testWidgets('flags duplicate and unusable links, and lists drives that failed to sync', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DriveSubmissionsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Fresh drive'), findsOneWidget);
    expect(find.text('The same drive as a submission above.'), findsOneWidget);
    expect(find.textContaining('Already synced as "DSA PYQs"'), findsOneWidget);
    expect(find.textContaining('The sync cannot read this link'), findsOneWidget);

    expect(find.text('Drives that failed to sync'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Tabulr cannot open this link.'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stopped drive leaves the failing list', (tester) async {
    await db.collection('acad_drives_sources').doc('Locked').update({'disabled': true});
    await tester.pumpWidget(const MaterialApp(home: DriveSubmissionsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Drives that failed to sync'), findsNothing);
  });
}
