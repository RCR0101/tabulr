import 'course.dart';

class Timetable {
  final List<Course> availableCourses;
  final List<SelectedSection> selectedSections;
  final List<ClashWarning> clashWarnings;

  Timetable({
    required this.availableCourses,
    required this.selectedSections,
    required this.clashWarnings,
  });

  Map<String, dynamic> toJson() {
    return {
      'availableCourses': availableCourses.map((c) => c.toJson()).toList(),
      'selectedSections': selectedSections.map((s) => s.toJson()).toList(),
      'clashWarnings': clashWarnings.map((w) => w.toJson()).toList(),
    };
  }

  factory Timetable.fromJson(Map<String, dynamic> json) {
    return Timetable(
      availableCourses: (json['availableCourses'] as List)
          .map((c) => Course.fromJson(c))
          .toList(),
      selectedSections: (json['selectedSections'] as List)
          .map((s) => SelectedSection.fromJson(s))
          .toList(),
      clashWarnings: (json['clashWarnings'] as List)
          .map((w) => ClashWarning.fromJson(w))
          .toList(),
    );
  }
}

class SelectedSection {
  final String courseCode;
  final String sectionId;
  final Section section;

  SelectedSection({
    required this.courseCode,
    required this.sectionId,
    required this.section,
  });

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'sectionId': sectionId,
      'section': section.toJson(),
    };
  }

  factory SelectedSection.fromJson(Map<String, dynamic> json) {
    return SelectedSection(
      courseCode: json['courseCode'],
      sectionId: json['sectionId'],
      section: Section.fromJson(json['section']),
    );
  }
}

class ClashWarning {
  final ClashType type;
  final String message;
  final List<String> conflictingCourses;
  final ClashSeverity severity;

  ClashWarning({
    required this.type,
    required this.message,
    required this.conflictingCourses,
    required this.severity,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'message': message,
      'conflictingCourses': conflictingCourses,
      'severity': severity.toString(),
    };
  }

  factory ClashWarning.fromJson(Map<String, dynamic> json) {
    return ClashWarning(
      type: ClashType.values.firstWhere(
        (e) => e.toString() == json['type'],
      ),
      message: json['message'],
      conflictingCourses: List<String>.from(json['conflictingCourses']),
      severity: ClashSeverity.values.firstWhere(
        (e) => e.toString() == json['severity'],
      ),
    );
  }
}

enum ClashType { 
  regularClass, 
  midSemExam, 
  endSemExam, 
  classAndExam 
}

enum ClashSeverity { 
  warning, 
  error 
}

class TimetableSlot {
  final DayOfWeek day;
  final List<int> hours;
  final String courseCode;
  final String sectionId;
  final String instructor;
  final String room;

  TimetableSlot({
    required this.day,
    required this.hours,
    required this.courseCode,
    required this.sectionId,
    required this.instructor,
    required this.room,
  });
}