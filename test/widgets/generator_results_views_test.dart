import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/core/timetable_generator_controller.dart';
import 'package:timetable_maker/services/core/timetable_ranker.dart';
import 'package:timetable_maker/widgets/generator/generator_results_views.dart';

void main() {
  testWidgets('hard-constraint empty state offers actionable relaxations', (
    tester,
  ) async {
    ConstraintRelaxation? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyResults(
            isGenerating: false,
            result: RankingResult(
              ranked: const [],
              activeAxes: const [],
              axisWeights: const {},
              unmetIntents: const ['No option meets the required window.'],
            ),
            relaxations: const [ConstraintRelaxation.hoursWindow],
            onRelax: (relaxation) => selected = relaxation,
          ),
        ),
      ),
    );

    expect(find.text('Allow classes outside the window'), findsOneWidget);
    await tester.tap(find.text('Allow classes outside the window'));
    expect(selected, ConstraintRelaxation.hoursWindow);
  });
}
