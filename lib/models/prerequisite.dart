class Prerequisite {
  final String prereqName;
  final String preCop;

  Prerequisite({
    required this.prereqName,
    required this.preCop,
  });

  factory Prerequisite.fromMap(Map<String, dynamic> map) {
    return Prerequisite(
      prereqName: map['prereq_name'] ?? '',
      preCop: map['pre_cop'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'prereq_name': prereqName,
      'pre_cop': preCop,
    };
  }
}

class CoursePrerequisites {
  final String name;
  final List<Prerequisite> prereqs;
  final String courseCode;
  final bool hasPrerequisites;
  final String? allOne; // "All" or "One" - indicates if all or one prereq is needed

  CoursePrerequisites({
    required this.name,
    required this.prereqs,
    required this.courseCode,
    required this.hasPrerequisites,
    this.allOne,
  });

  factory CoursePrerequisites.fromMap(Map<String, dynamic> map) {
    List<Prerequisite> prereqsList = [];
    if (map['prereqs'] != null) {
      prereqsList = (map['prereqs'] as List)
          .map((item) => Prerequisite.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    return CoursePrerequisites(
      name: map['name'] ?? '',
      prereqs: prereqsList,
      courseCode: map['course_code'] ?? '',
      hasPrerequisites: map['has_prerequisites'] ?? false,
      allOne: map['all_one'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'prereqs': prereqs.map((p) => p.toMap()).toList(),
      'course_code': courseCode,
      'has_prerequisites': hasPrerequisites,
      if (allOne != null) 'all_one': allOne,
    };
  }
}
