import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/admin/courses_master_management_screen.dart';
import 'package:timetable_maker/services/data/admin_data_service.dart';

import '../helpers/preview_harness.dart';

/// Renders the courses-master admin screen so the design can be looked at.
/// Writing the PNG is the point; there is nothing asserted here.
///
/// The fixture carries the rows this screen exists to fix — a missing title, a
/// zero-credit row, a hyphenated code and a non-Normal type — because a list of
/// tidy rows would not show whether those are legible.
void main() {
  setUpAll(loadPreviewFont);

  final rows = <Map<String, dynamic>>[
    {'course_code': 'BIO F110', 'title': 'BIOLOGICAL LABORATORY', 'credits': 1, 'type': 'Normal'},
    // Real Hyderabad rows: a hyphenated code, curated as ATC on one campus only.
    {'course_code': 'BITS F101-2', 'title': 'SOCIAL CONDUCT', 'credits': 0.5, 'type': 'ATC'},
    // The bug this screen is for: 0 credits where Hyderabad has 2.
    {'course_code': 'BITS U104', 'title': 'FOUND OF MEASUREMENT & EXPT', 'credits': 0, 'type': 'Normal'},
    {'course_code': 'CS F211', 'title': 'Data Structures and Algorithms', 'credits': 4, 'type': 'Normal'},
    // A code the uploader inserted with no usable title.
    {'course_code': 'CS F491', 'title': '', 'credits': 3, 'type': 'Project'},
    {'course_code': 'ECON F211', 'title': 'Principles of Economics', 'credits': 3, 'type': 'Normal'},
    {'course_code': 'MATH F211', 'title': 'Mathematics III', 'credits': 3, 'type': 'Normal'},
    {'course_code': 'PHY F213', 'title': 'Optics and Modern Physics for Engineering Applications', 'credits': 4, 'type': 'Normal'},
  ];

  Future<void> seed() async {
    final db = FakeFirebaseFirestore();
    for (final campus in ['hyderabad', 'pilani', 'goa']) {
      await db
          .collection('campuses')
          .doc(campus)
          .collection('catalog')
          .doc('courses_master')
          .set({'count': rows.length, 'entriesJson': jsonEncode(rows)});
    }
    AdminDataService()
      ..firestoreForTest = db
      ..invalidateAll();
  }

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('courses master admin — $name', (tester) async {
      usePreviewSurface(tester, const Size(2000, 1500));
      await seed();

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CoursesMasterManagementScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'courses_master_admin_$name');
    });

    testWidgets('courses master editor — $name', (tester) async {
      usePreviewSurface(tester, const Size(2000, 1500));
      await seed();

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CoursesMasterManagementScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      // The zero-credit row, i.e. the one an admin actually opens to fix.
      await tester.tap(find.text('BITS U104'));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'courses_master_editor_$name');
    });
  }

  tearDownAll(() => AdminDataService().firestoreForTest = null);
}
