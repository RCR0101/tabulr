import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course_history.dart';
import 'package:timetable_maker/screens/course_history_screen.dart';
import 'package:timetable_maker/services/data/course_history_service.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';

import '../helpers/preview_harness.dart';

/// Renders the course-history screen so the design can be looked at. Writing
/// the PNG is the point; there is nothing asserted here.
///
/// The fixture carries the awkward cases on purpose — a five-semester gap, a
/// course that only ever ran once, an eight-name instructor list and a title
/// long enough to need eliding — because the layout flatters itself on three
/// tidy rows — including the five-semester hole the real archive has between
/// 2021-22 and 2024-25, which the strip marks with a "/" rather than implying
/// the record is continuous.
///
/// Titles come from a seeded courses_master, not from the history bundle, which
/// is where the screen gets them: the parsed booklet titles are truncated at the
/// first line of a wrapped cell.
///
/// Names are spelled out in full. Abbreviating them ("N GOVEAS") made the
/// rendered preview look as though the placeholder filter had missed something —
/// bare initials ARE legitimate here (82 of 1,169 real names start with one, e.g.
/// "K VAISHALI", "B MISHRA"), which is exactly why a preview must not imply
/// otherwise.
void main() {
  setUpAll(loadPreviewFont);

  /// The first name is the instructor-in-charge unless [ic] says otherwise —
  /// the booklet capitalises whoever runs the course.
  Map<String, dynamic> offering(List<String> profs, int sections,
          {List<String>? ic}) =>
      {
        'instructors': profs,
        'ic': ic ?? (profs.isEmpty ? const [] : [profs.first]),
        'sections': sections,
      };

  // The curated catalogue the screen resolves titles through. These are the real
  // courses_master strings, which is why BIO F110 reads "BIOLOGICAL LABORATORY"
  // rather than the booklet's "BIOLOGY LABORATORY".
  const titles = {
    'BIO F110': 'BIOLOGICAL LABORATORY',
    'CS F211': 'Data Structures and Algorithms',
    'CS F407': 'Artificial Intelligence',
    'CS F469': 'Information Retrieval',
    'ECON F211': 'Principles of Economics',
    'MATH F211': 'Mathematics III',
    'PHY F213': 'Optics and Modern Physics for Engineering Applications',
  };

  final bundle = <Map<String, dynamic>>[
    {
      'term': '2020-21-1',
      'courses': {
        'BIO_F110': offering([
          'AMARTYA SANYAL',
          'BRAHMANDAM N S A L GAYATRI',
          'K VAISHALI',
          'P SANKAR GANESH',
          'ANINDITA THAKUR',
          'PIYUSH KHANDELIA',
          'KIRTIMAAN SYAL',
          'SUPRATIM GHOSH',
        ], 11),
        'CS_F211': offering(['RAVIPRASAD ADURI'], 4),
        'CS_F407': offering(['NEENA GOVEAS'], 1),
        'ECON_F211': offering(['SUDATTA SARANGI'], 3),
        'MATH_F211': offering(['PALLA DHANUMJAYA'], 6),
      },
    },
    {
      'term': '2020-21-2',
      'courses': {
        'BIO_F110': offering(['AMARTYA SANYAL'], 9),
        'CS_F211': offering(['CHITTARANJAN HOTA'], 5),
        'MATH_F211': offering(['PALLA DHANUMJAYA'], 6),
        'PHY_F213': offering(['SUBHASIS CHAKRABARTI', 'JAYENDRA N BANDYOPADHYAY'],
            2),
      },
    },
    {
      'term': '2021-22-1',
      'courses': {
        'CS_F211': offering(['CHITTARANJAN HOTA', 'RAVIPRASAD ADURI'], 6),
        'ECON_F211': offering(['SUDATTA SARANGI'], 3),
        'MATH_F211': offering(['PALLA DHANUMJAYA'], 6),
      },
    },
    {
      'term': '2025-26-2',
      'courses': {
        'BIO_F110': offering(['K VAISHALI'], 10),
        'MATH_F211': offering(['ANUPAMA RASTOGI'], 6),
        'PHY_F213': offering(['SUBHASIS CHAKRABARTI'],
            2),
      },
    },
    {
      'term': '2026-27-1',
      'courses': {
        'CS_F211': offering(['CHITTARANJAN HOTA', 'RAVIPRASAD ADURI', 'ANIRBAN BAGCHI'], 6),
        'MATH_F211': offering(['ANUPAMA RASTOGI'], 6),
        // First appearance: the "New" tag.
        // Nobody capitalised: 10 of 333 real courses print no in-charge.
        'CS_F469': offering(['ARYAN DALMIA'], 2, ic: const []),
        'ECON_F211': offering(['SUDATTA SARANGI'], 4),
      },
    },
  ];

  for (final (name, brightness) in previewBrightnesses) {
    testWidgets('course history — $name', (tester) async {
      // 2400 physical at 2.0 is 1200 logical — past the 600px mobile
      // breakpoint, so this is the row-sharing desktop layout.
      usePreviewSurface(tester, const Size(2400, 1700));
      CourseHistoryService().seedForTest(CourseHistory.fromBundle(bundle));
      CoursesMasterService().seedForTest([
        for (final entry in titles.entries)
          CourseMasterEntry(
              courseCode: entry.key,
              title: entry.value,
              credits: 3,
              type: 'Normal'),
      ]);

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CourseHistoryScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'course_history_$name');
    });

    testWidgets('course history phone — $name', (tester) async {
      usePreviewSurface(tester, const Size(820, 1400));
      CourseHistoryService().seedForTest(CourseHistory.fromBundle(bundle));
      CoursesMasterService().seedForTest([
        for (final entry in titles.entries)
          CourseMasterEntry(
              courseCode: entry.key,
              title: entry.value,
              credits: 3,
              type: 'Normal'),
      ]);

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CourseHistoryScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'course_history_phone_$name');
    });

    testWidgets('course history professors — $name', (tester) async {
      usePreviewSurface(tester, const Size(2400, 1700));
      CourseHistoryService().seedForTest(CourseHistory.fromBundle(bundle));
      CoursesMasterService().seedForTest([
        for (final entry in titles.entries)
          CourseMasterEntry(
              courseCode: entry.key,
              title: entry.value,
              credits: 3,
              type: 'Normal'),
      ]);

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CourseHistoryScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Professors'));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'course_history_profs_$name');
    });

    testWidgets('course history sheet — $name', (tester) async {
      usePreviewSurface(tester, const Size(2400, 1700));
      CourseHistoryService().seedForTest(CourseHistory.fromBundle(bundle));
      CoursesMasterService().seedForTest([
        for (final entry in titles.entries)
          CourseMasterEntry(
              courseCode: entry.key,
              title: entry.value,
              credits: 3,
              type: 'Normal'),
      ]);

      await tester.pumpWidget(RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(brightness),
          home: const CourseHistoryScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      // BIO F110: eleven sections, eight instructors, and two terms it skipped.
      await tester.tap(find.text('BIO F110'));
      await tester.pumpAndSettle();

      await capturePreview(tester, 'course_history_sheet_$name');
    });
  }
}
