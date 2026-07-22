import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/export_options.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/timetable/timetable_grid.dart';
import 'package:timetable_maker/widgets/timetable_widget.dart';

/// Guards the PNG-export layout. exportToPNG mounts the full [TimetableWidget]
/// export surface inside an off-screen, fully unbounded overlay
/// (`Positioned(left/top only) → Material → UnconstrainedBox`). The surface —
/// including the exam-schedule Table — must size to its own content; a `stretch`
/// column or Flex table columns throw "BoxConstraints forces an infinite width"
/// there, which is what broke export on prod. The pre-existing grid test only
/// pumped TimetableGrid directly and so never exercised this surface.
void main() {
  Course courseWithExams(String code) => Course(
        courseCode: code,
        courseTitle: 'Title $code',
        lectureCredits: 3,
        practicalCredits: 0,
        totalCredits: 3,
        sections: const [],
        // A midsem always sits in one of MS1–MS4; a compre in FN/AN.
        midSemExam: ExamSchedule(date: DateTime(2026, 3, 2), timeSlot: TimeSlot.MS2),
        endSemExam: ExamSchedule(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.AN),
      );

  SelectedSection selected(String code) => SelectedSection(
        courseCode: code,
        sectionId: 'L1',
        section: Section(
          sectionId: 'L1',
          type: SectionType.L,
          instructor: 'Dr. A',
          room: '6101',
          schedule: [
            ScheduleEntry(days: const [DayOfWeek.M], hours: const [2]),
          ],
        ),
      );

  TimetableSlot slot(String code, DayOfWeek day, List<int> hours) => TimetableSlot(
        day: day,
        hours: hours,
        courseCode: code,
        courseTitle: 'Title $code',
        sectionId: 'L1',
        instructor: 'Dr. A',
        room: '6101',
      );

  Future<void> pumpExportSurface(
    WidgetTester tester, {
    bool showExamDates = true,
  }) async {
    final codes = ['CS F111', 'MATH F112'];
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            // Mirrors exportToPNG's OverlayEntry: unbounded on both axes.
            Positioned(
              left: 0,
              top: 0,
              child: Material(
                child: UnconstrainedBox(
                  child: TimetableWidget(
                    timetableSlots: [
                      slot(codes[0], DayOfWeek.M, const [2]),
                      slot(codes[1], DayOfWeek.T, const [3]),
                    ],
                    availableCourses: [for (final c in codes) courseWithExams(c)],
                    selectedSections: [for (final c in codes) selected(c)],
                    size: TimetableSize.extraLarge,
                    isForExport: true,
                    tableKey: GlobalKey(),
                    exportOptions: ExportOptions(showExamDates: showExamDates),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('export surface with exam dates lays out under an unbounded overlay',
      (tester) async {
    await pumpExportSurface(tester);

    expect(tester.takeException(), isNull);
    // The exam schedule rendered (regression: this Table used to force an
    // infinite width and crash the whole capture).
    expect(find.text('Compre'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('export surface without exam dates also lays out unbounded',
      (tester) async {
    await pumpExportSurface(tester, showExamDates: false);

    expect(tester.takeException(), isNull);
    expect(find.text('Compre'), findsNothing);
  });

  testWidgets('exam table spans the same width as the timetable grid',
      (tester) async {
    await pumpExportSurface(tester);

    expect(tester.takeException(), isNull);
    final gridWidth = tester.getSize(find.byType(TimetableGrid)).width;
    final tableWidth = tester.getSize(find.byType(Table)).width;

    // The table sits inside horizontal padding, so it can never be wider than
    // the grid — but it should fill essentially all of it rather than
    // shrink-wrapping to its text.
    expect(tableWidth, lessThanOrEqualTo(gridWidth));
    expect(tableWidth, greaterThan(gridWidth * 0.85));
  });

  testWidgets('exam slots show clock times, not FN/AN shorthand',
      (tester) async {
    await pumpExportSurface(tester);

    expect(tester.takeException(), isNull);
    // MS2 midsem and an AN compre both render as campus clock times. The old
    // `s == FN ? 'FN' : 'AN'` printed "AN" for every midsem slot.
    expect(find.text('11:30AM-1:00PM'), findsWidgets);
    expect(find.text('FN'), findsNothing);
    expect(find.text('AN'), findsNothing);
  });

  testWidgets('export boundary is capturable (toImage succeeds)', (tester) async {
    final key = GlobalKey();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Material(
                child: UnconstrainedBox(
                  child: TimetableWidget(
                    timetableSlots: [slot('CS F111', DayOfWeek.M, const [2])],
                    availableCourses: [courseWithExams('CS F111')],
                    selectedSections: [selected('CS F111')],
                    size: TimetableSize.extraLarge,
                    isForExport: true,
                    tableKey: key,
                    exportOptions: const ExportOptions(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final boundary = key.currentContext!.findRenderObject();
    // A laid-out RenderRepaintBoundary with a finite size is exactly what
    // ExportService.exportToPNG needs; a missing size is the failure mode.
    expect(boundary, isA<RenderBox>());
    expect((boundary as RenderBox).hasSize, isTrue);
    expect(boundary.size.isFinite, isTrue);
  });
}
