import 'dart:math';

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

  // ── Property / metamorphic stress ────────────────────────────────────
  //
  // The cases above pin specific inputs to specific outputs. These fuzz
  // hundreds of randomised inputs and assert the same rules hold as
  // *invariants*, checked against an independent oracle. Each property
  // re-derives its cases from a fixed seed, so a failure is reproducible.

  const seed = 0x2A11C0DE;
  const iterations = 500;
  const eps = 1e-9;

  GeneratedTimetable randomTimetable(Random r, int idx) {
    final courses = 1 + r.nextInt(4);
    final sections = <ConstraintSelectedSection>[];
    final allDays = DayOfWeek.values;
    for (var i = 0; i < courses; i++) {
      final days = (allDays.toList()..shuffle(r)).take(1 + r.nextInt(2)).toList();
      final hours = <int>{};
      final hcount = 1 + r.nextInt(3);
      while (hours.length < hcount) {
        hours.add(1 + r.nextInt(12));
      }
      sections.add(ConstraintSelectedSection(
        courseCode: 'C$i',
        sectionId: 'S${r.nextInt(3)}',
        section: makeSection(days: days, hours: hours.toList(), instructor: 'P${r.nextInt(4)}'),
      ));
    }
    final hpd = {for (final d in DayOfWeek.values) d: 0};
    for (final s in sections) {
      for (final e in s.section.schedule) {
        for (final d in e.days) {
          hpd[d] = hpd[d]! + e.hours.length;
        }
      }
    }
    return GeneratedTimetable(
      id: 'tt$idx',
      sections: sections,
      pros: const [],
      cons: const [],
      hoursPerDay: hpd,
      optionalCourseCodes: const {},
    );
  }

  TimetableConstraints randomConstraints(Random r) {
    final freeDays = (DayOfWeek.values.toList()..shuffle(r)).take(r.nextInt(3)).toList();
    int? early = r.nextBool() ? 1 + r.nextInt(6) : null;
    int? late = r.nextBool() ? 6 + r.nextInt(6) : null;
    return TimetableConstraints(
      freeDayPreference: freeDays,
      minimizeGaps: r.nextBool(),
      protectLunchBreak: r.nextBool(),
      earliestStartSlot: early,
      latestEndSlot: late,
      timeOfDayPreference: TimeOfDayPreference.values[r.nextInt(TimeOfDayPreference.values.length)],
      preferredInstructors: r.nextBool() ? ['P${r.nextInt(4)}'] : const [],
    );
  }

  bool dominates(RankedTimetable a, RankedTimetable b, List<RankAxis> axes) {
    var strictly = false;
    for (final ax in axes) {
      final va = a.axisSatisfaction[ax]!;
      final vb = b.axisSatisfaction[ax]!;
      if (va < vb - eps) return false;
      if (va > vb + eps) strictly = true;
    }
    return strictly;
  }

  test('ranker invariants hold across $iterations random pools', () {
    final r = Random(seed);
    for (var iter = 0; iter < iterations; iter++) {
      final n = 1 + r.nextInt(9);
      final pool = [for (var i = 0; i < n; i++) randomTimetable(r, i)];
      final c = randomConstraints(r);
      final res = TimetableRanker.rank(pool, c, const []);
      final axes = res.activeAxes;
      final ranked = res.ranked;

      // 1. Size preserved, ids conserved.
      expect(ranked.length, n, reason: 'pool size must be preserved');
      expect(ranked.map((e) => e.timetable.id).toSet(), pool.map((e) => e.id).toSet());

      // 2. Bounds + axis-key consistency.
      for (final e in ranked) {
        expect(e.tier, greaterThanOrEqualTo(1));
        expect(e.closeness, inInclusiveRange(0.0, 1.0));
        expect(e.axisSatisfaction.keys.toSet(), axes.toSet());
        for (final v in e.axisSatisfaction.values) {
          expect(v, inInclusiveRange(-eps, 1 + eps));
        }
      }

      // 3. Sorted by tier ascending, then closeness descending.
      for (var i = 1; i < ranked.length; i++) {
        final prev = ranked[i - 1];
        final cur = ranked[i];
        expect(cur.tier, greaterThanOrEqualTo(prev.tier));
        if (cur.tier == prev.tier) {
          expect(cur.closeness, lessThanOrEqualTo(prev.closeness + eps));
        }
      }
      expect(ranked.first.tier, 1, reason: 'the top pick is always a best trade-off');

      // 4. Pareto correctness — tier 1 iff non-dominated; tier>1 dominated by a
      //    strictly lower tier. Oracle recomputed independently from the
      //    exposed axis satisfaction vectors.
      for (final e in ranked) {
        final dominated = ranked.any((o) => o != e && dominates(o, e, axes));
        expect(e.tier == 1, equals(!dominated), reason: 'tier-1 == non-dominated');
        if (e.tier > 1) {
          expect(
            ranked.any((o) => o.tier < e.tier && dominates(o, e, axes)),
            isTrue,
            reason: 'a lower-tier option must dominate any compromise',
          );
        }
      }

      // 5. TOPSIS closeness matches an independent recomputation from the
      //    exposed axis satisfaction + weights.
      for (final e in ranked) {
        var dPlus = 0.0, dMinus = 0.0;
        for (final ax in axes) {
          final w = res.axisWeights[ax]!;
          final wv = w * e.axisSatisfaction[ax]!;
          dPlus += (wv - w) * (wv - w);
          dMinus += wv * wv;
        }
        dPlus = sqrt(dPlus);
        dMinus = sqrt(dMinus);
        final expected = (dPlus + dMinus) < eps ? 0.5 : dMinus / (dPlus + dMinus);
        expect(e.closeness, closeTo(expected, 1e-9), reason: 'closeness must equal the TOPSIS formula');
      }

      // 6. Weights (when present) form a convex combination.
      if (axes.isNotEmpty) {
        final sum = res.axisWeights.values.fold(0.0, (a, b) => a + b);
        expect(sum, closeTo(1.0, 1e-9));
      }
    }
  });

  test('ranking is deterministic for identical input', () {
    final r = Random(seed ^ 0x99);
    for (var iter = 0; iter < 100; iter++) {
      final n = 1 + r.nextInt(8);
      final pool = [for (var i = 0; i < n; i++) randomTimetable(r, i)];
      final c = randomConstraints(r);
      final a = TimetableRanker.rank(pool, c, const []);
      final b = TimetableRanker.rank(pool, c, const []);
      expect(
        a.ranked.map((e) => '${e.timetable.id}:${e.tier}:${e.closeness.toStringAsFixed(9)}').toList(),
        b.ranked.map((e) => '${e.timetable.id}:${e.tier}:${e.closeness.toStringAsFixed(9)}').toList(),
      );
    }
  });

  test('hard-constraint filter matches its predicate for random inputs', () {
    final r = Random(seed ^ 0x5151);
    for (var iter = 0; iter < 400; iter++) {
      final tt = randomTimetable(r, iter);
      final freeDays = (DayOfWeek.values.toList()..shuffle(r)).take(r.nextInt(3)).toList();
      final c = TimetableConstraints(
        earliestStartSlot: r.nextBool() ? 1 + r.nextInt(6) : null,
        latestEndSlot: r.nextBool() ? 6 + r.nextInt(6) : null,
        requireHoursWindow: r.nextBool(),
        freeDayPreference: freeDays,
        requireFreeDays: r.nextBool(),
        protectLunchBreak: r.nextBool(),
        requireLunchFree: r.nextBool(),
      );

      final hoursOutside = tt.sections.expand((s) => s.section.schedule).expand((e) => e.hours).any((h) =>
          (c.earliestStartSlot != null && h < c.earliestStartSlot!) ||
          (c.latestEndSlot != null && h > c.latestEndSlot!));
      final freeViolated = c.freeDayPreference.any((d) => (tt.hoursPerDay[d] ?? 0) != 0);
      final lunchViolated = tt.sections.expand((s) => s.section.schedule).expand((e) => e.hours).any((h) => h == 5 || h == 6);

      final windowActive = c.requireHoursWindow && (c.earliestStartSlot != null || c.latestEndSlot != null);
      final freeActive = c.requireFreeDays && c.freeDayPreference.isNotEmpty;
      final lunchActive = c.requireLunchFree && c.protectLunchBreak;

      final expected = !(windowActive && hoursOutside) && !(freeActive && freeViolated) && !(lunchActive && lunchViolated);

      expect(TimetableRanker.meetsHardConstraints(tt, c), expected);
      expect(TimetableRanker.hasHardConstraints(c), windowActive || freeActive || lunchActive);
    }
  });
}


