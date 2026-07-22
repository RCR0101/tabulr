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

  // Calculate SGPA for this semester
  double get sgpa {
    if (courses.isEmpty) return 0.0;

    // Only consider Normal courses with grades
    final normalCourses =
        courses
            .where(
              (c) =>
                  c.courseType == CourseType.normal &&
                  c.grade != null &&
                  c.grade!.isNotEmpty,
            )
            .toList();

    if (normalCourses.isEmpty) return 0.0;

    final totalGradePoints = normalCourses.fold<double>(
      0.0,
      (sum, course) => sum + course.totalGradePoints,
    );

    final totalCredits = normalCourses.fold<double>(
      0.0,
      (sum, course) => sum + course.credits,
    );

    return totalCredits > 0 ? totalGradePoints / totalCredits : 0.0;
  }

  // Get total credits for this semester (only Normal courses)
  double get totalCredits {
    return courses
        .where(
          (c) =>
              c.courseType == CourseType.normal &&
              c.grade != null &&
              c.grade!.isNotEmpty,
        )
        .fold<double>(0.0, (sum, course) => sum + course.credits);
  }

  // Get total grade points for this semester (only Normal courses)
  double get totalGradePoints {
    return courses
        .where(
          (c) =>
              c.courseType == CourseType.normal &&
              c.grade != null &&
              c.grade!.isNotEmpty,
        )
        .fold<double>(0.0, (sum, course) => sum + course.totalGradePoints);
  }

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

  /// Semesters in chronological order.
  ///
  /// The backing map's iteration order cannot be trusted: it comes from
  /// Firestore, which returns documents sorted lexicographically by ID, so
  /// 'ST 1' lands after '5-2' rather than after '2-2'. Ordering by
  /// [SemesterConstants.all] (the same list the calculator screen uses) is what
  /// makes "latest attempt" actually mean latest. Semesters with names outside
  /// that list keep their map order and sort last.
  Iterable<SemesterData> get _chronologicalSemesters {
    final known = SemesterConstants.all.toSet();
    return [
      for (final name in SemesterConstants.all)
        if (semesters[name] != null) semesters[name]!,
      for (final entry in semesters.entries)
        if (!known.contains(entry.key)) entry.value,
    ];
  }

  // Returns one CourseEntry per course code, keeping only the latest semester's attempt.
  List<CourseEntry> _deduplicatedCourses() {
    final latest = <String, CourseEntry>{};
    for (final semester in _chronologicalSemesters) {
      for (final course in semester.courses) {
        if (course.courseType != CourseType.normal ||
            course.grade == null ||
            course.grade!.isEmpty) {
          continue;
        }
        latest[course.courseCode] = course;
      }
    }
    return latest.values.toList();
  }

  int get uniqueCourseCount => _deduplicatedCourses().length;

  double get effectiveTotalCredits {
    return _deduplicatedCourses().fold<double>(0.0, (sum, c) => sum + c.credits);
  }

  double get effectiveTotalGradePoints {
    return _deduplicatedCourses().fold<double>(0.0, (sum, c) => sum + c.totalGradePoints);
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
