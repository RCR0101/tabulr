class AllCourse {
  final String courseCode;
  final String courseTitle;
  final double creditValue;
  final String type;

  AllCourse({
    required this.courseCode,
    required this.courseTitle,
    required this.creditValue,
    required this.type,
  });

  double get credits => creditValue;

  factory AllCourse.fromFirestore(Map<String, dynamic> data) {
    return AllCourse(
      courseCode: data['course_code'] as String? ?? '',
      courseTitle: data['title'] as String? ?? '',
      creditValue: (data['credits'] as num?)?.toDouble() ?? 0,
      type: data['type'] as String? ?? 'Normal',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_code': courseCode,
      'title': courseTitle,
      'credits': creditValue,
      'type': type,
    };
  }
}
