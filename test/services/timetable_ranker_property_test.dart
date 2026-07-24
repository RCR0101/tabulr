import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_ranker.dart';
import '../helpers/test_data.dart';

/// Property / fuzz coverage for [TimetableRanker]: instead of a few hand-picked
/// pools, generate hundreds of random ones and assert the invariants that must
/// hold for *every* input — Pareto correctness, tier ordering, and that the
/// reported TOPSIS closeness actually matches the exposed axis values.
void main() {
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
