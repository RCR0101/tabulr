class AllCourse {
  final String courseCode;
  final String courseTitle;

  /// The unit count. 0 for a course the booklet publishes only in contact
  /// hours — read [credits], which falls back to those.
  final double creditValue;

  /// Contact hours, where the booklet gives them instead of units.
  final double creditHours;
  final String type;

  AllCourse({
    required this.courseCode,
    required this.courseTitle,
    required this.creditValue,
    this.creditHours = 0,
    required this.type,
  });

  /// What to weight a grade by.
  ///
  /// Falls back to contact hours when no unit count is published, because the
  /// alternative is 0 — and a 0 does not merely display wrong, it drops the
  /// course out of the CGPA denominator entirely, silently changing the
  /// average. Hours are the weight that batch is graded on.
  double get credits => creditValue > 0 ? creditValue : creditHours;

  /// Whether [credits] is contact hours rather than units, so it can be
  /// labelled as such instead of quietly reading as units.
  bool get isInCreditHours => creditValue <= 0 && creditHours > 0;

  factory AllCourse.fromFirestore(Map<String, dynamic> data) {
    return AllCourse(
      courseCode: data['course_code'] as String? ?? '',
      courseTitle: data['title'] as String? ?? '',
      creditValue: (data['credits'] as num?)?.toDouble() ?? 0,
      creditHours: (data['credit_hours'] as num?)?.toDouble() ?? 0,
      type: data['type'] as String? ?? 'Normal',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_code': courseCode,
      'title': courseTitle,
      'credits': creditValue,
      if (creditHours > 0) 'credit_hours': creditHours,
      'type': type,
    };
  }
}
