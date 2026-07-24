import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_generator.dart';
import 'package:timetable_maker/services/core/timetable_ranker.dart';
import '../helpers/test_data.dart';

/// Side-by-side harness: generates real candidates, then compares the current
/// linear score ordering against the Pareto + TOPSIS ranker so we can see how
/// they diverge on the same feasible set. Prints a readable report and asserts
/// the ranker's invariants.
void main() {
  test('ranker vs current score — comparison report', () async {
    final courses = fiveCourseRealistic();
    final constraints = TimetableConstraints(
      mandatoryCourses: courses.map((c) => c.courseCode).toList(),
      // A mix of intents so several axes stay active.
      freeDayPreference: [DayOfWeek.F],
      earliestStartSlot: 2, // prefer no 8 AM (slot 1)
      minimizeGaps: true,
    );

    // Candidates come back already sorted by the current linear score.
    final candidates = await TimetableGenerator.generateTimetables(
      courses,
      constraints,
      maxTimetables: 30,
    );
    expect(candidates, isNotEmpty);

    final result = TimetableRanker.rank(candidates, constraints, courses);

    // ── Report ────────────────────────────────────────────────────────────
    final buf = StringBuffer('\n══════ Ranker comparison (${candidates.length} feasible candidates) ══════\n');
    buf.writeln('Active axes: ${result.activeAxes.map((a) => a.label).join(', ')}');
    buf.writeln('Weights: ${{for (final e in result.axisWeights.entries) e.key.label: e.value.toStringAsFixed(2)}}');
    if (result.unmetIntents.isNotEmpty) {
      buf.writeln('Diagnosis:');
      for (final n in result.unmetIntents) {
        buf.writeln('  • $n');
      }
    }

    buf.writeln('\n-- Pareto tier + TOPSIS closeness (top 6) --');
    for (final r in result.ranked.take(6)) {
      final sat = result.activeAxes
          .map((a) => '${a.label.split(' ').first}:${(r.axisSatisfaction[a] ?? 0).toStringAsFixed(2)}')
          .join(' ');
      final weak = r.weakAxes.isEmpty ? '' : '  relaxes[${r.weakAxes.map((a) => a.label).join(', ')}]';
      buf.writeln('  T${r.tier} c=${r.closeness.toStringAsFixed(2)}  ${r.timetable.id}   [$sat]$weak');
    }

    final tier1 = result.ranked.where((r) => r.tier == 1).length;
    buf.writeln('\nTier-1 (best trade-offs) size: $tier1 / ${candidates.length}');
    // ignore: avoid_print
    print(buf.toString());

    // ── Invariants ────────────────────────────────────────────────────────
    expect(result.ranked.length, candidates.length);
    expect(result.ranked.first.tier, 1); // top pick is always a best trade-off
    for (final r in result.ranked) {
      expect(r.tier, greaterThanOrEqualTo(1));
      expect(r.closeness, inInclusiveRange(0.0, 1.0));
    }
    // Tiers must be non-decreasing down the sorted list.
    for (var i = 1; i < result.ranked.length; i++) {
      expect(result.ranked[i].tier, greaterThanOrEqualTo(result.ranked[i - 1].tier));
    }
  });

  test('crafted trade-off surfaces a multi-option Pareto front', () async {
    // C1: L1 crams Monday (free T/W/Th/F but a heavy day); L2 spreads M/W/F
    // (light days but fewer free days). C2 mirrors the trade-off on Tue/Thu.
    // No single combo wins on both "free days" and "light days".
    final courses = [
      makeCourse(courseCode: 'C1 F101', sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1, 2, 3, 4]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
      ]),
      makeCourse(courseCode: 'C2 F102', sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1, 2, 3]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.T, DayOfWeek.Th], hours: [1]),
      ]),
    ];
    final constraints = TimetableConstraints(
      mandatoryCourses: ['C1 F101', 'C2 F102'],
      minimizeGaps: true,
    );

    final candidates = await TimetableGenerator.generateTimetables(courses, constraints, maxTimetables: 30);
    final result = TimetableRanker.rank(candidates, constraints, courses);

    final buf = StringBuffer('\n══════ Crafted trade-off (${candidates.length} candidates) ══════\n');
    buf.writeln('Active axes: ${result.activeAxes.map((a) => a.label).join(', ')}');
    for (final r in result.ranked) {
      final sat = result.activeAxes.map((a) => '${a.label.split(' ').first}:${(r.axisSatisfaction[a] ?? 0).toStringAsFixed(2)}').join(' ');
      buf.writeln('  T${r.tier} c=${r.closeness.toStringAsFixed(2)}  ${r.timetable.id}  [$sat]');
    }
    final tier1 = result.ranked.where((r) => r.tier == 1).length;
    buf.writeln('Tier-1 (incomparable best trade-offs): $tier1');
    // ignore: avoid_print
    print(buf.toString());

    // The whole point: more than one option is a genuine best trade-off.
    expect(tier1, greaterThanOrEqualTo(2));
  });

  test('axis importance steers which best trade-off ranks first', () async {
    // Same free-days-vs-light-days front as above: several incomparable tier-1
    // options. The user's importance picks should decide which leads.
    final courses = [
      makeCourse(courseCode: 'C1 F101', sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1, 2, 3, 4]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
      ]),
      makeCourse(courseCode: 'C2 F102', sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1, 2, 3]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.T, DayOfWeek.Th], hours: [1]),
      ]),
    ];
    final c = TimetableConstraints(mandatoryCourses: ['C1 F101', 'C2 F102'], minimizeGaps: true);
    final candidates = await TimetableGenerator.generateTimetables(courses, c, maxTimetables: 30);

    final freeFirst = TimetableRanker.rank(candidates, c, courses,
        importance: {RankAxis.freeDays: AxisImportance.high}).ranked.first;
    final lightFirst = TimetableRanker.rank(candidates, c, courses,
        importance: {RankAxis.lightLoad: AxisImportance.high}).ranked.first;

    // Prioritising free days surfaces a more free-day-rich top, and vice versa.
    expect(freeFirst.axisSatisfaction[RankAxis.freeDays]!,
        greaterThanOrEqualTo(lightFirst.axisSatisfaction[RankAxis.freeDays]!));
    expect(lightFirst.axisSatisfaction[RankAxis.lightLoad]!,
        greaterThanOrEqualTo(freeFirst.axisSatisfaction[RankAxis.lightLoad]!));
    // The two emphases genuinely lead to different top picks.
    expect(freeFirst.timetable.id, isNot(lightFirst.timetable.id));
  });

  group('hard constraints', () {
    GeneratedTimetable ttWith(List<Section> sections) {
      final secs = [
        for (var i = 0; i < sections.length; i++)
          ConstraintSelectedSection(courseCode: 'C$i', sectionId: sections[i].sectionId, section: sections[i]),
      ];
      final hpd = {for (final d in DayOfWeek.values) d: 0};
      for (final s in secs) {
        for (final e in s.section.schedule) {
          for (final d in e.days) {
            hpd[d] = hpd[d]! + e.hours.length;
          }
        }
      }
      return GeneratedTimetable(id: 't', sections: secs, pros: const [], cons: const [], hoursPerDay: hpd);
    }

    test('hours window filter rejects classes outside the required window', () {
      final c = TimetableConstraints(earliestStartSlot: 3, requireHoursWindow: true); // no class before 10 AM
      final early = ttWith([makeSection(days: [DayOfWeek.M], hours: [1])]); // 8 AM
      final ok = ttWith([makeSection(days: [DayOfWeek.M], hours: [4, 5])]);
      expect(TimetableRanker.meetsHardConstraints(early, c), isFalse);
      expect(TimetableRanker.meetsHardConstraints(ok, c), isTrue);
    });

    test('free-day filter rejects a busy required-free day', () {
      final c = TimetableConstraints(freeDayPreference: [DayOfWeek.F], requireFreeDays: true);
      final busyFri = ttWith([makeSection(days: [DayOfWeek.F], hours: [2])]);
      final freeFri = ttWith([makeSection(days: [DayOfWeek.M], hours: [2])]);
      expect(TimetableRanker.meetsHardConstraints(busyFri, c), isFalse);
      expect(TimetableRanker.meetsHardConstraints(freeFri, c), isTrue);
    });

    test('lunch filter rejects classes in the lunch slots', () {
      final c = TimetableConstraints(protectLunchBreak: true, requireLunchFree: true);
      final lunchClass = ttWith([makeSection(days: [DayOfWeek.M], hours: [5])]);
      final noLunch = ttWith([makeSection(days: [DayOfWeek.M], hours: [2])]);
      expect(TimetableRanker.meetsHardConstraints(lunchClass, c), isFalse);
      expect(TimetableRanker.meetsHardConstraints(noLunch, c), isTrue);
    });

    test('an unset require flag has no effect', () {
      final c = TimetableConstraints(earliestStartSlot: 3); // window set but not required
      final early = ttWith([makeSection(days: [DayOfWeek.M], hours: [1])]);
      expect(TimetableRanker.hasHardConstraints(c), isFalse);
      expect(TimetableRanker.meetsHardConstraints(early, c), isTrue);
    });

    test('diagnosis distinguishes individually-impossible from a joint conflict', () {
      final onlyFriMorning = [ttWith([makeSection(days: [DayOfWeek.F], hours: [1])])];

      // A single impossible requirement names itself.
      final soloReq = TimetableConstraints(freeDayPreference: [DayOfWeek.F], requireFreeDays: true);
      final soloNotes = TimetableRanker.hardConflictDiagnosis(onlyFriMorning, soloReq);
      expect(soloNotes, isNotEmpty);
      expect(soloNotes.first, contains('preference instead'));

      // Two individually-satisfiable requirements that clash only together.
      final both = [
        ttWith([makeSection(days: [DayOfWeek.M], hours: [1])]), // fits window, busy... free F yes
        ttWith([makeSection(days: [DayOfWeek.F], hours: [4])]), // free F no, fits window
      ];
      final jointReq = TimetableConstraints(
        earliestStartSlot: 3, requireHoursWindow: true,
        freeDayPreference: [DayOfWeek.F], requireFreeDays: true,
      );
      final jointNotes = TimetableRanker.hardConflictDiagnosis(both, jointReq);
      expect(jointNotes.any((n) => n.contains('all your required constraints at once')), isTrue);
    });
  });

  test('degenerate pool (no distinguishing intent) is handled', () async {
    final courses = [
      makeCourse(
        courseCode: 'CS F111',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])],
      ),
    ];
    final constraints = TimetableConstraints(mandatoryCourses: ['CS F111']);
    final candidates = await TimetableGenerator.generateTimetables(courses, constraints);

    final result = TimetableRanker.rank(candidates, constraints, courses);
    expect(result.ranked.length, candidates.length);
    // With a single feasible shape there's nothing to separate — all tier 1.
    expect(result.ranked.every((r) => r.tier == 1), isTrue);
  });
}
