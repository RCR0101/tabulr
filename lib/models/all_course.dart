// Model representing a course from the all_courses collection
class AllCourse {
  final String courseCode;
  final String courseTitle;
  final String u; // Credits (can be like "3" or "3*")
  final String type; // 'Normal' or 'ATC'

  AllCourse({
    required this.courseCode,
    required this.courseTitle,
    required this.u,
    required this.type,
  });

  // Parse credits value, removing any asterisk
  double get credits {
    final cleanU = u.replaceAll('*', '').trim();
    return double.tryParse(cleanU) ?? 0.0;
  }

  factory AllCourse.fromFirestore(Map<String, dynamic> data) {
    return AllCourse(
      courseCode: data['course_code'] as String? ?? '',
      courseTitle: data['course_title'] as String? ?? '',
      u: data['u'] as String? ?? '0',
      type: data['type'] as String? ?? 'Normal',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_code': courseCode,
      'course_title': courseTitle,
      'u': u,
      'type': type,
    };
  }
}
