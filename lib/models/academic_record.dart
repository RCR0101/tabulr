import '../constants/app_constants.dart';
import '../utils/course_code.dart';
import 'cgpa_data.dart';

/// What the student has already completed, derived from their CGPA record.
///
/// The CGPA calculator is the only part of the app that knows this, and its
/// data is encrypted per-user — so every consumer has to cope with an empty
/// record: never filled in, signed out, or decryption failed. [isEmpty] is the
/// signal to hide progress UI outright rather than render a row of zeros.
class AcademicRecord {
  /// Latest letter-graded attempt per course, keyed by [normalizeCode].
  final Map<String, CourseAttempt> attempts;
  final double cgpa;

  const AcademicRecord({required this.attempts, required this.cgpa});

  static const AcademicRecord empty = AcademicRecord(attempts: {}, cgpa: 0);

  bool get isEmpty => attempts.isEmpty;
  bool get isNotEmpty => attempts.isNotEmpty;

  /// Course codes are spaced inconsistently across sources, so every lookup
  /// goes through this rather than comparing raw strings. See
  /// [normalizeCourseCode], which admin course matching shares.
  static String normalizeCode(String code) => normalizeCourseCode(code);

  CourseAttempt? attemptFor(String code) => attempts[normalizeCode(code)];

  String? gradeFor(String code) => attemptFor(code)?.entry.grade;

  /// Cleared it. `E` is a letter grade but a failing one (clause 5.02), so it
  /// counts as attempted, not completed.
  bool hasPassed(String code) {
    final grade = gradeFor(code);
    return grade != null && grade != GradeConstants.failingGrade;
  }

  /// Attempted and failed — worth showing differently from "not taken yet".
  bool hasFailed(String code) => gradeFor(code) == GradeConstants.failingGrade;

  /// CGPA across just [codes] — the figure clause 5.02(iv) sets a 4.50 floor on
  /// for a minor, which is not the same as the overall CGPA.
  ///
  /// Returns null when none of them have been graded yet, so callers can tell
  /// "no data" apart from a genuine 0.0.
  double? cgpaAcross(Iterable<String> codes) {
    double points = 0;
    double credits = 0;
    for (final code in codes) {
      final entry = attemptFor(code)?.entry;
      if (entry == null) continue;
      points += entry.totalGradePoints;
      credits += entry.credits;
    }
    if (credits <= 0) return null;
    return points / credits;
  }
}
