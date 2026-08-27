import 'dart:math';

import '../../constants/app_constants.dart';

/// A grade assignment across a semester's courses and the CGPA it yields.
///
/// [totalGradePoints] is the "effort" — summed grade points — so the *easiest*
/// way to hit a target sorts first.
typedef GradeAssignment = ({
  Map<String, String> grades, // courseCode -> letter grade
  double resultingCgpa,
  double totalGradePoints,
});

/// What a target CGPA demands of one upcoming semester.
class CgpaTargetSolution {
  /// The average grade point the semester's courses must reach, weighted by
  /// credits — the single headline number ("you need to average X.XX").
  final double requiredSemesterAvg;

  /// The best CGPA reachable if every planned course got an A.
  final double maxAchievableCgpa;

  /// Whether the target is reachable at all this semester.
  final bool feasible;

  /// Grade assignments to show, ranked. When [feasible], the easiest ways to hit
  /// the target (least total grade points) come first; when not, the closest we
  /// can get (highest CGPA) come first. Every option respects the priority order
  /// (a higher-priority course is never graded below a lower-priority one).
  final List<GradeAssignment> options;

  const CgpaTargetSolution({
    required this.requiredSemesterAvg,
    required this.maxAchievableCgpa,
    required this.feasible,
    required this.options,
  });
}

/// Solves "what grades do I need this semester to reach a target CGPA".
///
/// Replaces the Grade Planner's old split — exact brute force for <=6 courses,
/// a biased hand-picked heuristic for 7+ that could miss the real answer and
/// present a worse one as "best". Grades are enumerated over the priority order
/// as a non-increasing run (a higher-priority course never gets a worse grade
/// than a lower-priority one): that is both what makes the ranking mean
/// something and what shrinks the space from gradesⁿ to C(n+g-1, g-1) — a few
/// thousand for a real semester — small enough to enumerate in full on the UI
/// thread. So the result is always optimal, never a sampled sliver.
class CgpaTargetSolver {
  const CgpaTargetSolver._();

  static CgpaTargetSolution solve({
    required double priorCredits,
    required double priorGradePoints,
    required List<({String code, double credits})> courses, // high -> low priority
    required double targetCgpa,
    int maxResults = 10,
  }) {
    // Ordered best -> worst: 'A'(10) .. 'E'(2). Index 0 is the best grade, so a
    // non-increasing run of grade points is a non-decreasing run of indices.
    final letters = GradeConstants.normal;
    final pts = GradeConstants.points;

    final n = courses.length;
    final semCredits = courses.fold<double>(0, (s, c) => s + c.credits);
    final denom = priorCredits + semCredits;

    double cgpaFor(double semPts) =>
        denom > 0 ? (priorGradePoints + semPts) / denom : 0.0;

    final maxCgpa = cgpaFor(semCredits * pts.first);
    final requiredAvg =
        semCredits > 0 ? (targetCgpa * denom - priorGradePoints) / semCredits : 0.0;

    final meeting = <GradeAssignment>[];
    final closest = <GradeAssignment>[]; // only consulted if nothing meets target
    final idx = List<int>.filled(n, 0);

    void emit() {
      double semPts = 0;
      for (var i = 0; i < n; i++) {
        semPts += courses[i].credits * pts[idx[i]];
      }
      final cg = cgpaFor(semPts);
      final grades = {for (var i = 0; i < n; i++) courses[i].code: letters[idx[i]]};
      final a = (grades: grades, resultingCgpa: cg, totalGradePoints: semPts);
      // 1e-9 so a grade that lands exactly on the target isn't dropped by float slop.
      (cg + 1e-9 >= targetCgpa ? meeting : closest).add(a);
    }

    void rec(int pos, int minIdx) {
      if (pos == n) {
        emit();
        return;
      }
      for (var g = minIdx; g < letters.length; g++) {
        idx[pos] = g;
        rec(pos + 1, g);
      }
    }

    if (n > 0) rec(0, 0);

    // Spread between the best and worst grade in an assignment. Among equally
    // cheap options, the tighter one ("all B" over "an A and a C") is the more
    // realistic ask, so it sorts first.
    double spread(GradeAssignment a) {
      final vals = a.grades.values.map(GradeConstants.pointsFor);
      return vals.reduce(max) - vals.reduce(min);
    }

    final List<GradeAssignment> options;
    if (meeting.isNotEmpty) {
      meeting.sort((a, b) {
        final byEffort = a.totalGradePoints.compareTo(b.totalGradePoints);
        return byEffort != 0 ? byEffort : spread(a).compareTo(spread(b));
      });
      options = meeting.take(maxResults).toList();
    } else {
      closest.sort((a, b) => b.resultingCgpa.compareTo(a.resultingCgpa));
      options = closest.take(maxResults).toList();
    }

    return CgpaTargetSolution(
      requiredSemesterAvg: requiredAvg,
      maxAchievableCgpa: maxCgpa,
      feasible: meeting.isNotEmpty,
      options: options,
    );
  }
}
