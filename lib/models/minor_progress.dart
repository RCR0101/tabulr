import 'academic_record.dart';
import 'minor_programme.dart';

/// How far a student is through one minor, measured against their CGPA record.
///
/// The Bulletin lists a minor's courses; the CGPA record says which have been
/// cleared. Neither side alone answers "am I close to this?", which is the
/// question a student browsing minors actually has.
class MinorProgress {
  /// Courses of this minor cleared with a letter grade other than E.
  final List<MinorCourse> cleared;

  /// Courses attempted but not cleared (grade E). Kept apart from [cleared]
  /// because they still need repeating.
  final List<MinorCourse> failed;

  /// Units from [cleared] only. Courses with no unit count in the Bulletin
  /// contribute nothing, so this can understate — see [unitsAreComplete].
  final int clearedUnits;

  /// False when any cleared course had no unit count to add up, meaning
  /// [clearedUnits] is a floor rather than an exact figure.
  final bool unitsAreComplete;

  /// CGPA across the cleared courses — the figure clause 5.02(iv) puts a 4.50
  /// floor on. Null when nothing is graded yet.
  final double? cgpaInMinor;

  /// Courses the minor needs, per the Bulletin. Falls back to the count of
  /// listed courses when the Bulletin gives no explicit minimum.
  final int requiredCourses;

  const MinorProgress({
    required this.cleared,
    required this.failed,
    required this.clearedUnits,
    required this.unitsAreComplete,
    required this.cgpaInMinor,
    required this.requiredCourses,
  });

  static const MinorProgress none = MinorProgress(
    cleared: [],
    failed: [],
    clearedUnits: 0,
    unitsAreComplete: true,
    cgpaInMinor: null,
    requiredCourses: 0,
  );

  /// The BITS-wide minimum for a minor (clause 5.02(iv)).
  static const double minimumCgpa = 4.5;

  int get clearedCount => cleared.length;

  bool get hasStarted => cleared.isNotEmpty || failed.isNotEmpty;

  /// 0–1, capped: clearing more than the minimum does not overfill the bar.
  double get fraction {
    if (requiredCourses <= 0) return 0;
    return (clearedCount / requiredCourses).clamp(0.0, 1.0);
  }

  bool get meetsCourseCount =>
      requiredCourses > 0 && clearedCount >= requiredCourses;

  /// Null when nothing is graded yet — "unknown", not "below".
  bool? get meetsCgpa =>
      cgpaInMinor == null ? null : cgpaInMinor! >= minimumCgpa;

  static MinorProgress of(MinorProgramme minor, AcademicRecord record) {
    if (record.isEmpty) return none;

    final cleared = <MinorCourse>[];
    final failed = <MinorCourse>[];
    var units = 0;
    var unitsComplete = true;

    for (final group in minor.groups) {
      for (final course in group.courses) {
        if (record.hasFailed(course.code)) {
          failed.add(course);
        } else if (record.hasPassed(course.code)) {
          cleared.add(course);
          if (course.units == null) {
            unitsComplete = false;
          } else {
            units += course.units!;
          }
        }
      }
    }

    return MinorProgress(
      cleared: cleared,
      failed: failed,
      clearedUnits: units,
      unitsAreComplete: unitsComplete,
      cgpaInMinor: record.cgpaAcross(cleared.map((c) => c.code)),
      requiredCourses: minor.minCourses ?? minor.courseCount,
    );
  }
}
