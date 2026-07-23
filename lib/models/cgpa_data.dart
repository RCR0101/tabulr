import '../constants/app_constants.dart';
import 'course_type.dart';

class CourseEntry {
  final String courseCode;
  final String courseTitle;
  final double credits;
  final CourseType courseType;
  String? grade;

  CourseEntry({
    required this.courseCode,
    required this.courseTitle,
    required this.credits,
    required this.courseType,
    this.grade,
  });

  double get gradePoints {
    if (courseType == CourseType.atc) return 0.0;
    return GradeConstants.pointsFor(grade ?? '');
  }

  /// Whether this attempt counts toward SGPA/CGPA.
  ///
  /// Only graded (non-ATC) courses carrying a *letter* grade do. An NC — like
  /// any other report — is excluded from both the grade points and the units
  /// (Academic Regulations 4.21).
  bool get countsTowardCgpa =>
      courseType == CourseType.normal && GradeConstants.isLetterGrade(grade);

  double get totalGradePoints => credits * gradePoints;

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'credits': credits,
      'courseType': courseType.toJson(),
      'grade': grade,
    };
  }

  factory CourseEntry.fromJson(Map<String, dynamic> json) {
    return CourseEntry(
      courseCode: json['courseCode'] as String,
      courseTitle: json['courseTitle'] as String,
      credits: (json['credits'] as num).toDouble(),
      courseType: CourseType.fromJson(json['courseType'] as String),
      grade: json['grade'] as String?,
    );
  }

  CourseEntry copyWith({
    String? courseCode,
    String? courseTitle,
    double? credits,
    CourseType? courseType,
    String? grade,
  }) {
    return CourseEntry(
      courseCode: courseCode ?? this.courseCode,
      courseTitle: courseTitle ?? this.courseTitle,
      credits: credits ?? this.credits,
      courseType: courseType ?? this.courseType,
      grade: grade ?? this.grade,
    );
  }
}

// Model representing a single semester
class SemesterData {
  final String semesterName;
  final List<CourseEntry> courses;

  SemesterData({required this.semesterName, List<CourseEntry>? courses})
    : courses = courses ?? [];

  /// The courses in this semester that count toward a grade average — normal
  /// courses carrying a letter grade. Reports (NC) and ATC courses are out.
  Iterable<CourseEntry> get _gradedCourses =>
      courses.where((c) => c.countsTowardCgpa);

  // Calculate SGPA for this semester
  double get sgpa {
    final graded = _gradedCourses;
    if (graded.isEmpty) return 0.0;
    final credits = totalCredits;
    return credits > 0 ? totalGradePoints / credits : 0.0;
  }

  // Get total credits for this semester (only Normal courses)
  double get totalCredits =>
      _gradedCourses.fold<double>(0.0, (sum, course) => sum + course.credits);

  // Get total grade points for this semester (only Normal courses)
  double get totalGradePoints => _gradedCourses.fold<double>(
      0.0, (sum, course) => sum + course.totalGradePoints);

  Map<String, dynamic> toJson() {
    return {
      'semesterName': semesterName,
      'courses': courses.map((c) => c.toJson()).toList(),
    };
  }

  factory SemesterData.fromJson(Map<String, dynamic> json) {
    return SemesterData(
      semesterName: json['semesterName'] as String,
      courses:
          (json['courses'] as List<dynamic>)
              .map((c) => CourseEntry.fromJson(c as Map<String, dynamic>))
              .toList(),
    );
  }

  SemesterData copyWith({String? semesterName, List<CourseEntry>? courses}) {
    return SemesterData(
      semesterName: semesterName ?? this.semesterName,
      courses: courses ?? this.courses,
    );
  }
}

/// A course's most recent attempt and the semester it was taken in.
typedef CourseAttempt = ({String semester, CourseEntry entry});

/// One point on the CGPA trajectory: a semester's SGPA and the cumulative CGPA
/// standing after it.
typedef CgpaTrajectoryPoint = ({
  String semester,
  double sgpa,
  double cumulativeCgpa,
  double credits,
});

// Model representing the complete CGPA data
class CGPAData {
  final Map<String, SemesterData> semesters;
  final DateTime lastUpdated;

  CGPAData({Map<String, SemesterData>? semesters, DateTime? lastUpdated})
    : semesters = semesters ?? {},
      lastUpdated = lastUpdated ?? DateTime.now();

  // Calculate overall CGPA (only counts the latest attempt for repeated courses)
  double get cgpa {
    if (semesters.isEmpty) return 0.0;

    final effectiveCourses = _deduplicatedCourses();
    final totalGradePoints = effectiveCourses.fold<double>(
      0.0, (sum, c) => sum + c.totalGradePoints);
    final totalCredits = effectiveCourses.fold<double>(
      0.0, (sum, c) => sum + c.credits);

    return totalCredits > 0 ? totalGradePoints / totalCredits : 0.0;
  }

  /// Semesters in chronological order, paired with their name.
  ///
  /// The backing map's iteration order cannot be trusted: it comes from
  /// Firestore, which returns documents sorted lexicographically by ID, so
  /// 'ST 1' lands after '5-2' rather than after '2-2'. Ordering by
  /// [SemesterConstants.all] (the same list the calculator screen uses) is what
  /// makes "latest attempt" actually mean latest. Semesters with names outside
  /// that list keep their map order and sort last.
  Iterable<MapEntry<String, SemesterData>> get _chronologicalSemesters {
    final known = SemesterConstants.all.toSet();
    return [
      for (final name in SemesterConstants.all)
        if (semesters[name] != null) MapEntry(name, semesters[name]!),
      for (final entry in semesters.entries)
        if (!known.contains(entry.key)) entry,
    ];
  }

  /// The most recent *letter-graded* attempt of every course, keyed by code.
  ///
  /// Academic Regulations 4.21: a new grade "will replace the earlier one in
  /// the calculation of CGPA", but where "merely a report emerges, this event
  /// by itself will not alter the CGPA". So a later NC does not displace an
  /// earlier letter grade — it is skipped, and the earlier grade stands.
  ///
  /// Shared by CGPA, Grade Planner and CG Booster so all three agree on which
  /// attempt is current. Pass [excludingSemester] to get the standing *before*
  /// a semester, which is what the planner projects from.
  Map<String, CourseAttempt> latestAttempts({String? excludingSemester}) {
    final latest = <String, CourseAttempt>{};
    for (final entry in _chronologicalSemesters) {
      if (excludingSemester != null && entry.key == excludingSemester) continue;
      for (final course in entry.value.courses) {
        if (!course.countsTowardCgpa) continue;
        latest[course.courseCode] = (semester: entry.key, entry: course);
      }
    }
    return latest;
  }

  // Returns one CourseEntry per course code, keeping only the latest semester's attempt.
  List<CourseEntry> _deduplicatedCourses() =>
      latestAttempts().values.map((a) => a.entry).toList();

  int get uniqueCourseCount => _deduplicatedCourses().length;

  double get effectiveTotalCredits {
    return _deduplicatedCourses().fold<double>(0.0, (sum, c) => sum + c.credits);
  }

  double get effectiveTotalGradePoints {
    return _deduplicatedCourses().fold<double>(0.0, (sum, c) => sum + c.totalGradePoints);
  }

  /// Semesters in chronological order (public view of the internal ordering).
  List<MapEntry<String, SemesterData>> get orderedSemesters =>
      _chronologicalSemesters.toList();

  /// Per-semester SGPA paired with the running CGPA *after* that semester, in
  /// chronological order. Semesters with no graded course are skipped (they add
  /// no point) but still contribute nothing to the running total. This is the
  /// series behind the trajectory chart.
  List<CgpaTrajectoryPoint> trajectory() {
    final points = <CgpaTrajectoryPoint>[];
    final running = <String, SemesterData>{};
    for (final entry in _chronologicalSemesters) {
      running[entry.key] = entry.value;
      if (entry.value.totalCredits <= 0) continue;
      final cumulative = CGPAData(semesters: Map.of(running)).cgpa;
      points.add((
        semester: entry.key,
        sgpa: entry.value.sgpa,
        cumulativeCgpa: cumulative,
        credits: entry.value.totalCredits,
      ));
    }
    return points;
  }

  /// How many of each letter grade the student holds, counting only the latest
  /// attempt of every course. Keyed by grade ('A', 'A-', …).
  Map<String, int> gradeDistribution() {
    final dist = <String, int>{};
    for (final attempt in latestAttempts().values) {
      final g = attempt.entry.grade;
      if (GradeConstants.isLetterGrade(g)) {
        dist[g!] = (dist[g] ?? 0) + 1;
      }
    }
    return dist;
  }

  /// The SGPA a future semester of [nextCredits] credits must average to lift the
  /// CGPA to [targetCgpa], given the current standing. May exceed 10 (target
  /// unreachable in one semester) or go negative (already past target) — callers
  /// present those cases rather than clamping silently.
  double requiredSgpa({required double targetCgpa, required double nextCredits}) {
    if (nextCredits <= 0) return 0.0;
    final curCredits = effectiveTotalCredits;
    final curPoints = effectiveTotalGradePoints;
    return (targetCgpa * (curCredits + nextCredits) - curPoints) / nextCredits;
  }

  Map<String, dynamic> toJson() {
    return {
      'semesters': semesters.map((key, value) => MapEntry(key, value.toJson())),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory CGPAData.fromJson(Map<String, dynamic> json) {
    final semestersMap = (json['semesters'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, SemesterData.fromJson(value as Map<String, dynamic>)),
    );

    return CGPAData(
      semesters: semestersMap,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  CGPAData copyWith({
    Map<String, SemesterData>? semesters,
    DateTime? lastUpdated,
  }) {
    return CGPAData(
      semesters: semesters ?? this.semesters,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
