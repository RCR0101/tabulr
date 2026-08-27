import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_ranker.dart';
import 'package:timetable_maker/widgets/generated_timetable_card.dart';
import '../helpers/test_data.dart';

RankedTimetable _sampleRanked({
  required int tier,
  required double closeness,
  List<RankAxis> weak = const [],
}) {
  final tt = GeneratedTimetable(
    id: '3-day week, light days',
    sections: [
      ConstraintSelectedSection(
        courseCode: 'CS F111',
        sectionId: 'L1',
        section: makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
      ),
    ],
    pros: const ['Compact week'],
    cons: const [],
    hoursPerDay: {
      for (final d in DayOfWeek.values) d: d == DayOfWeek.M ? 1 : 0,
    },
    totalCredits: 4,
  );
  return RankedTimetable(
    timetable: tt,
    tier: tier,
    closeness: closeness,
    axisSatisfaction: {RankAxis.freeDays: 1.0, RankAxis.lightLoad: 0.4},
    weakAxes: weak,
  );
}

void main() {
  Widget host(
    RankedTimetable r, {
    List<RankAxis> protectableAxes = const [],
    ValueChanged<RankAxis>? onProtect,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GeneratedTimetableCard(
          ranked: r,
          onSelect: () {},
          protectableAxes: protectableAxes,
          onProtectAxis: onProtect,
        ),
      ),
    ),
  );

  testWidgets('renders tier badge, fit %, and relaxed-axis hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_sampleRanked(tier: 1, closeness: 0.82, weak: [RankAxis.lightLoad])),
    );

    expect(find.text('Best trade-off'), findsOneWidget);
    expect(find.text('Fit 82%'), findsOneWidget);
    expect(find.textContaining('relaxes light days'), findsOneWidget);
    // Descriptive name, no ordering prefix.
    expect(find.text('3-day week, light days'), findsOneWidget);
  });

  testWidgets('a lower tier reads as a compromise, not "best"', (tester) async {
    await tester.pumpWidget(host(_sampleRanked(tier: 3, closeness: 0.2)));
    expect(find.text('Best trade-off'), findsNothing);
    expect(find.text('Tier 3'), findsOneWidget);
  });

  testWidgets('tapping the tier opens the trade-off explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_sampleRanked(tier: 1, closeness: 0.82, weak: [RankAxis.lightLoad])),
    );

    await tester.tap(find.text('Fit 82%'));
    await tester.pumpAndSettle();

    expect(find.text('Why this rank?'), findsWidgets);
    expect(find.text('Free days'), findsOneWidget);
    expect(find.text('Light, compact days'), findsOneWidget);
    expect(find.textContaining('best trade-off'), findsOneWidget);
  });

  testWidgets('can protect a measurable strength from the explanation', (
    tester,
  ) async {
    RankAxis? protected;
    await tester.pumpWidget(
      host(
        _sampleRanked(tier: 1, closeness: 0.82),
        protectableAxes: const [RankAxis.freeDays],
        onProtect: (axis) => protected = axis,
      ),
    );

    await tester.tap(find.text('Fit 82%'));
    await tester.pumpAndSettle();
    expect(find.text('Keep free days'), findsOneWidget);

    await tester.tap(find.text('Keep free days'));
    await tester.pumpAndSettle();
    expect(protected, RankAxis.freeDays);
  });
}
