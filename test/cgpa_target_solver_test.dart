import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/models/course_type.dart';
import 'package:timetable_maker/services/core/cgpa_target_solver.dart';

// Grade points of a letter, for expectations.
double _p(String g) => GradeConstants.pointsFor(g);

void main() {
  group('CgpaTargetSolver', () {
    test('easiest way to hit an exact target, from a clean slate', () {
      final sol = CgpaTargetSolver.solve(
        priorCredits: 0,
        priorGradePoints: 0,
        courses: const [(code: 'X', credits: 3), (code: 'Y', credits: 3)],
        targetCgpa: 8.0,
      );
      expect(sol.feasible, isTrue);
      // 8.0 average over two equal courses is straight B/B — the cheapest hit.
      expect(sol.options.first.grades, {'X': 'B', 'Y': 'B'});
      expect(sol.options.first.resultingCgpa, closeTo(8.0, 1e-9));
      expect(sol.requiredSemesterAvg, closeTo(8.0, 1e-9));
    });

    test('unreachable target reports infeasible and the closest (all-A)', () {
      // Standing: 30 credits at a flat 4.0 -> 120 grade points.
      final sol = CgpaTargetSolver.solve(
        priorCredits: 30,
        priorGradePoints: 120,
        courses: const [(code: 'X', credits: 3)],
        targetCgpa: 9.0,
      );
      expect(sol.feasible, isFalse);
      expect(sol.maxAchievableCgpa, closeTo(150 / 33, 1e-9));
      expect(sol.options.first.grades, {'X': 'A'});
    });

    test('respects priority: a higher-ranked course is never graded lower', () {
      final sol = CgpaTargetSolver.solve(
        priorCredits: 0,
        priorGradePoints: 0,
        courses: const [
          (code: 'A', credits: 3),
          (code: 'B', credits: 3),
          (code: 'C', credits: 3),
        ],
        targetCgpa: 7.6,
      );
      for (final opt in sol.options) {
        final g = ['A', 'B', 'C'].map((c) => _p(opt.grades[c]!)).toList();
        for (var i = 0; i + 1 < g.length; i++) {
          expect(g[i], greaterThanOrEqualTo(g[i + 1]),
              reason: 'priority order must be non-increasing in grade points');
        }
      }
    });

    // The whole point of the rewrite: the old >6-course path sampled a sliver and
    // could miss the real answer. Prove optimality by brute-forcing the FULL
    // grades^n space independently and matching the solver's top result.
    test('returns the true min-effort optimum (vs full brute force)', () {
      final courses = const [
        (code: 'A', credits: 4.0),
        (code: 'B', credits: 3.0),
        (code: 'C', credits: 3.0),
        (code: 'D', credits: 2.0),
      ];
      const prior = 45.0, priorPts = 45.0 * 6.5; // some arbitrary standing
      const target = 7.0; // reachable here (all-A tops out ~7.24)
      final letters = GradeConstants.normal;
      final pts = GradeConstants.points;
      final semC = courses.fold<double>(0, (s, c) => s + c.credits);
      final denom = prior + semC;

      // Independent brute force over every assignment, keeping only those that
      // respect priority (non-increasing points) and meet the target.
      double? bestEffort;
      final n = courses.length;
      final idx = List<int>.filled(n, 0);
      void walk(int pos) {
        if (pos == n) {
          for (var i = 0; i + 1 < n; i++) {
            if (pts[idx[i]] < pts[idx[i + 1]]) return; // violates priority
          }
          double semPts = 0;
          for (var i = 0; i < n; i++) {
            semPts += courses[i].credits * pts[idx[i]];
          }
          if ((priorPts + semPts) / denom + 1e-9 >= target) {
            if (bestEffort == null || semPts < bestEffort!) bestEffort = semPts;
          }
          return;
        }
        for (var g = 0; g < letters.length; g++) {
          idx[pos] = g;
          walk(pos + 1);
        }
      }
      walk(0);

      final sol = CgpaTargetSolver.solve(
        priorCredits: prior,
        priorGradePoints: priorPts,
        courses: courses,
        targetCgpa: target,
      );
      expect(sol.feasible, isTrue);
      expect(sol.options.first.totalGradePoints, closeTo(bestEffort!, 1e-9));
    });

    test('standingBefore drops a retaken course so it is not double-counted', () {
      CourseEntry entry(String code, String grade) => CourseEntry(
            courseCode: code,
            courseTitle: code,
            credits: 3,
            courseType: CourseType.normal,
            grade: grade,
          );
      final data = CGPAData(semesters: {
        '1-1': SemesterData(semesterName: '1-1', courses: [entry('P', 'D')]),
        '1-2': SemesterData(semesterName: '1-2', courses: [entry('Q', 'A')]),
      });

      // Planning 1-2 and retaking P there: P's old attempt must be excluded so
      // its credits aren't counted twice once the projection adds the retake.
      final s = data.standingBefore(semester: '1-2', replacedCodes: {'P'});
      expect(s.credits, 0); // only P was outside 1-2, and it's being replaced
      expect(s.gradePoints, 0);
    });
  });
}
