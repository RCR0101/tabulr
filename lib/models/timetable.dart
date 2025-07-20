import 'course.dart';
import '../services/campus_service.dart';

class Timetable {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Campus campus;
  final List<Course> availableCourses;
  final List<SelectedSection> selectedSections;
  final List<ClashWarning> clashWarnings;

  Timetable({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.campus,
    required this.availableCourses,
    required this.selectedSections,
    required this.clashWarnings,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'campus': CampusService.getCampusCode(campus),
      'availableCourses': availableCourses.map((c) => c.toJson()).toList(),
      'selectedSections': selectedSections.map((s) => s.toJson()).toList(),
      'clashWarnings': clashWarnings.map((w) => w.toJson()).toList(),
    };
  }

  factory Timetable.fromJson(Map<String, dynamic> json) {
    // Parse campus, defaulting to hyderabad if not specified
    Campus parsedCampus = Campus.hyderabad;
    if (json['campus'] != null) {
      final campusCode = json['campus'] as String;
      if (campusCode == 'pilani') {
        parsedCampus = Campus.pilani;
      } else if (campusCode == 'hyderabad') {
        parsedCampus = Campus.hyderabad;
      }
    }
    
    return Timetable(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled Timetable',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : DateTime.now(),
      campus: parsedCampus,
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
  final String courseTitle;
  final String sectionId;
  final String instructor;
  final String room;

  TimetableSlot({
    required this.day,
    required this.hours,
    required this.courseCode,
    required this.courseTitle,
    required this.sectionId,
    required this.instructor,
    required this.room,
  });
}