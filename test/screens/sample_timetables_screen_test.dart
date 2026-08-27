import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/sample_timetables_screen.dart';
import 'package:timetable_maker/services/core/sample_timetable_service.dart';
import 'package:timetable_maker/widgets/auto_load_cdc_dialog.dart';

void main() {
  testWidgets('starts with CDC selection inline instead of opening a dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SampleTimetablesScreen(courseLoader: () async => const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start with your core package'), findsOneWidget);
    expect(find.byType(AutoLoadCDCSelector), findsOneWidget);
    expect(find.byType(AutoLoadCDCDialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Generate samples'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Change opens a prefilled CDC dialog after generation', (
    tester,
  ) async {
    final pick = AutoLoadCDCResult(primaryBranch: 'A7', semester: '1-1');
    await tester.pumpWidget(
      MaterialApp(
        home: SampleTimetablesScreen(
          initialPick: pick,
          courseLoader: () async => const [],
          sampleBuilder:
              (_, __) async =>
                  const SampleTimetables(codes: ['CS F111'], samples: []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(AutoLoadCDCDialog), findsNothing);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.byType(AutoLoadCDCDialog), findsOneWidget);
    expect(find.text('A7 - Computer Science'), findsOneWidget);
    expect(find.text('Semester 1-1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
