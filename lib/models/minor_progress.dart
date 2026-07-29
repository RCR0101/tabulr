import 'academic_record.dart';
import 'minor_programme.dart';

/// How far one group of a minor is along — "2 of 3 core done".
///
/// Split out from the minor-wide total because the two answer different
/// questions: a student with five electives and no core courses is nowhere
/// near the minor, however good the overall count looks.
class MinorGroupProgress {
  const MinorGroupProgress({
    required this.name,
    required this.required,
    required this.cleared,
    required this.listed,
  });

  final String name;

  /// Null when the Bulletin gives no minimum for this group on its own.
  final int? required;
  final int cleared;
  final int listed;

  /// Null when [required] is unknown — "can't tell", not "no".
  bool? get isSatisfied => required == null ? null : cleared >= required!;
}

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

  /// Per-group breakdown, in the minor's own group order.
  final List<MinorGroupProgress> groups;

  const MinorProgress({
    required this.cleared,
    required this.failed,
    required this.clearedUnits,
    required this.unitsAreComplete,
    required this.cgpaInMinor,
    required this.requiredCourses,
    this.groups = const [],
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

  /// Every group with a stated minimum is satisfied. Clearing enough courses
  /// overall is not the same thing — the core ones are not optional.
  bool get meetsGroups =>
      groups.every((g) => g.isSatisfied ?? true);

  /// The coursework is done: enough courses overall, and none of them standing
  /// in for a core course it cannot replace.
  bool get meetsCoursework => meetsCourseCount && meetsGroups;

  /// Null when nothing is graded yet — "unknown", not "below".
  bool? get meetsCgpa =>
      cgpaInMinor == null ? null : cgpaInMinor! >= minimumCgpa;

  static MinorProgress of(MinorProgramme minor, AcademicRecord record) {
    if (record.isEmpty) return none;

    final cleared = <MinorCourse>[];
    final failed = <MinorCourse>[];
    // The code the student actually cleared, which for an alternative row is
    // not the one the Bulletin prints first — the CGPA has to be averaged over
    // what they took.
    final clearedCodes = <String>[];
    final groups = <MinorGroupProgress>[];
    var units = 0;
    var unitsComplete = true;

    for (final group in minor.groups) {
      var clearedHere = 0;
      for (final course in group.courses) {
        final passed = course.codes.where(record.hasPassed).toList();
        if (passed.isNotEmpty) {
          cleared.add(course);
          clearedCodes.add(passed.first);
          clearedHere++;
          if (course.units == null) {
            unitsComplete = false;
          } else {
            units += course.units!;
          }
        } else if (course.codes.any(record.hasFailed)) {
          failed.add(course);
        }
      }
      groups.add(MinorGroupProgress(
        name: group.name,
        required: group.required,
        cleared: clearedHere,
        listed: group.courses.length,
      ));
    }

    return MinorProgress(
      cleared: cleared,
      failed: failed,
      clearedUnits: units,
      unitsAreComplete: unitsComplete,
      cgpaInMinor: record.cgpaAcross(clearedCodes),
      requiredCourses: minor.minCourses ?? minor.courseCount,
      groups: groups,
    );
  }
}
