import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/acad_drives_service.dart';
import 'package:timetable_maker/widgets/acad_drives/acad_feedback_dialogs.dart';
import 'package:timetable_maker/widgets/acad_drives/my_submissions_view.dart';

Future<void> drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  group('My submissions', () {
    MySubmission sub(String status, {Map<String, dynamic>? sync, String? note}) => MySubmission(
          id: status,
          title: 'Drive $status${sync == null ? '' : ' synced'}',
          driveLink: 'https://drive.google.com/drive/folders/x',
          status: status,
          reviewNote: note,
          syncedAt: sync == null ? null : DateTime(2026, 10, 5),
          syncedFiles: sync?['files'] as int?,
          syncProblem: sync?['problem'] as String?,
        );

    testWidgets('shows where each submission has got to', (tester) async {
      final items = [
        sub('pending'),
        sub('approved'),
        sub('approved', sync: {'files': 37}),
        sub('approved', sync: {'files': 0, 'problem': 'Share it as "Anyone with the link".'}),
        sub('rejected', note: 'Not academic'),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MySubmissionsView(stream: Stream.value(items))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Live · 37 files'), findsOneWidget);
      expect(find.text('Could not sync'), findsOneWidget);
      expect(find.text('Share it as "Anyone with the link".'), findsOneWidget);
      expect(find.text('Not added'), findsOneWidget);
      expect(find.text('Not academic'), findsOneWidget);
    });

    testWidgets('says so when there is nothing yet', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MySubmissionsView(stream: Stream.value(const []))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining("haven't submitted"), findsOneWidget);
    });

    test('reads the sync status the crawler mirrors onto the submission', () async {
      final db = FakeFirebaseFirestore();
      AcadDrivesService.firestoreForTest = db;
      addTearDown(() => AcadDrivesService.firestoreForTest = null);
      await db.collection('acad_drives_submissions').doc('a').set({
        'title': 'Mine', 'driveLink': 'https://d', 'status': 'approved', 'submittedBy': 'me@x',
        'syncStatus': {'files': 3, 'problem': null},
      });
      await db.collection('acad_drives_submissions').doc('b').set({
        'title': 'Theirs', 'driveLink': 'https://d', 'status': 'pending', 'submittedBy': 'you@x',
      });
      final mine = await AcadDrivesService().mySubmissions('me@x').first;
      expect(mine.map((s) => s.title), ['Mine']);
      expect(mine.single.syncedFiles, 3);
    });
  });

  group('Report a problem', () {
    testWidgets('needs the right course before a wrong-course report can be sent', (tester) async {
      final sent = Completer<List<Object?>>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReportFileForm(
            file: const {'id': 'f1', 'name': 'DBMS midsem.pdf', 'course_codes': ['CS F211'], 'resource_type': 'pyq'},
            pickCourse: (_) async => 'CS F212',
            onSubmit: (p, c, t, n) async => sent.complete([p, c, t, n]),
          ),
        ),
      ));
      expect(find.text('Filed under CS F211 · shown as Past papers'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Send report');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.tap(find.text(AcadFileProblem.wrongCourse.label));
      await tester.pump();
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.text('Pick the right course'));
      await tester.pumpAndSettle();
      expect(find.text('Should be: CS F212'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'this is DBMS');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(await sent.future, [AcadFileProblem.wrongCourse, 'CS F212', null, 'this is DBMS']);
      await drainToasts(tester);
    });

    testWidgets('a broken-file report needs nothing more', (tester) async {
      AcadFileProblem? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReportFileForm(
            file: const {'id': 'f1', 'name': 'x.pdf'},
            onSubmit: (p, c, t, n) async => got = p,
          ),
        ),
      ));
      await tester.tap(find.text(AcadFileProblem.broken.label));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
      await tester.pumpAndSettle();
      expect(got, AcadFileProblem.broken);
      await drainToasts(tester);
    });
  });

  group('Ask for resources', () {
    testWidgets('sends one request per type picked', (tester) async {
      List<String>? types;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RequestResourcesForm(
            course: 'CS F212',
            onSubmit: (t, note) async {
              types = t;
              return t.length;
            },
          ),
        ),
      ));
      await tester.tap(find.text('Past papers'));
      await tester.tap(find.text('Solutions'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
      await tester.pumpAndSettle();
      expect(types, unorderedEquals(['pyq', 'solutions']));
      await drainToasts(tester);
    });

    test('request ids make asking twice the same document', () {
      expect(AcadDrivesService.requestId('CS F212', 'pyq', 'f20220123H'), 'CS_F212__pyq__f20220123H');
      expect(AcadDrivesService.requestId(' CS  F212 ', 'pyq', 'f20220123H'), 'CS_F212__pyq__f20220123H');
    });
  });
}
