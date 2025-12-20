// Model representing a single course entry in a semester
class CourseEntry {
  final String courseCode;
  final String courseTitle;
  final double credits; // The 'u' field from all_courses
  final String courseType; // 'Normal' or 'ATC'
  String?
  grade; // For Normal: A, A-, B, B-, C, C-, D, D-, E, NC; For ATC: GD, PR, NC

  CourseEntry({
    required this.courseCode,
    required this.courseTitle,
    required this.credits,
    required this.courseType,
    this.grade,
  });

  // Get grade points based on grade and course type
  double get gradePoints {
    if (courseType == 'ATC') return 0.0; // ATC courses don't carry grade points

    switch (grade) {
      case 'A':
        return 10.0;
      case 'A-':
        return 9.0;
      case 'B':
        return 8.0;
      case 'B-':
        return 7.0;
      case 'C':
        return 6.0;
      case 'C-':
        return 5.0;
      case 'D':
        return 4.0;
      case 'D-':
        return 3.0;
      case 'E':
        return 2.0;
      case 'NC':
        return 0.0;
      default:
        return 0.0;
    }
  }

  // Get total grade points (credits * grade points)
  double get totalGradePoints => credits * gradePoints;

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'credits': credits,
      'courseType': courseType,
      'grade': grade,
    };
  }

  factory CourseEntry.fromJson(Map<String, dynamic> json) {
    return CourseEntry(
      courseCode: json['courseCode'] as String,
      courseTitle: json['courseTitle'] as String,
      credits: (json['credits'] as num).toDouble(),
      courseType: json['courseType'] as String,
      grade: json['grade'] as String?,
    );
  }

  CourseEntry copyWith({
    String? courseCode,
    String? courseTitle,
    double? credits,
    String? courseType,
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
                  c.courseType == 'Normal' &&
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
              c.courseType == 'Normal' &&
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
              c.courseType == 'Normal' &&
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

  // Calculate overall CGPA
  double get cgpa {
    if (semesters.isEmpty) return 0.0;

    double totalGradePoints = 0.0;
    double totalCredits = 0.0;

    for (final semester in semesters.values) {
      totalGradePoints += semester.totalGradePoints;
      totalCredits += semester.totalCredits;
    }

    return totalCredits > 0 ? totalGradePoints / totalCredits : 0.0;
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
