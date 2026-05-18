import '../services/courses_master_service.dart';

class Prerequisite {
  final String courseCode;
  final String type;

  Prerequisite({
    required this.courseCode,
    required this.type,
  });

  String get displayName => CoursesMasterService().getTitle(courseCode);

  factory Prerequisite.fromMap(Map<String, dynamic> map) {
    return Prerequisite(
      courseCode: map['course_code'] ?? '',
      type: map['type'] ?? 'pre',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'course_code': courseCode,
      'type': type,
    };
  }
}

class CoursePrerequisites {
  final String courseCode;
  final List<Prerequisite> prereqs;
  final bool hasPrerequisites;
  final String? allOne;

  CoursePrerequisites({
    required this.courseCode,
    required this.prereqs,
    required this.hasPrerequisites,
    this.allOne,
  });

  String get displayName => CoursesMasterService().getTitle(courseCode);

  factory CoursePrerequisites.fromMap(Map<String, dynamic> map) {
    List<Prerequisite> prereqsList = [];
    if (map['prereqs'] != null) {
      prereqsList = (map['prereqs'] as List)
          .map((item) => Prerequisite.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    return CoursePrerequisites(
      courseCode: map['course_code'] ?? '',
      prereqs: prereqsList,
      hasPrerequisites: map['has_prerequisites'] ?? false,
      allOne: map['all_one'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'course_code': courseCode,
      'prereqs': prereqs.map((p) => p.toMap()).toList(),
      'has_prerequisites': hasPrerequisites,
      if (allOne != null) 'all_one': allOne,
    };
  }
}
