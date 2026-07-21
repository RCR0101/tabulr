import 'campus.dart';
import 'course.dart';
import '../utils/datetime_utils.dart';

class Timetable {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Campus campus;

  /// Full course catalog for this campus+semester — embedded so the timetable
  /// is self-contained even offline.
  final List<Course> availableCourses;

  /// The sections the user has chosen (one L/P/T per course).
  final List<SelectedSection> selectedSections;
  final List<ClashWarning> clashWarnings;

  /// Non-null when the timetable has been shared via a public link.
  final String? shareId;
  int projectCount;

  /// Academic term this timetable was built in, e.g. "2026-2027_sem1".
  ///
  /// Course selections do not survive a semester rollover — the student takes a
  /// different set of courses — so a timetable from a past term is a historical
  /// record, not something to reconcile against the current catalog. Mutable so
  /// unstamped timetables can adopt the current term on first load.
  ///
  /// Null on timetables created before term tracking existed.
  String? term;

  Timetable({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.campus,
    required this.availableCourses,
    required this.selectedSections,
    required this.clashWarnings,
    this.shareId,
    this.projectCount = 0,
    this.term,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'campus': campus.code,
      'availableCourses': availableCourses.map((c) => c.toJson()).toList(),
      'selectedSections': selectedSections.map((s) => s.toJson()).toList(),
      'clashWarnings': clashWarnings.map((w) => w.toJson()).toList(),
      if (shareId != null) 'shareId': shareId,
      if (projectCount > 0) 'projectCount': projectCount,
      if (term != null) 'term': term,
    };
  }

  Map<String, dynamic> toFirestoreJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'campus': campus.code,
      'selectedSections': selectedSections.map((s) => s.toJson()).toList(),
      'clashWarnings': clashWarnings.map((w) => w.toJson()).toList(),
      if (shareId != null) 'shareId': shareId,
      if (projectCount > 0) 'projectCount': projectCount,
      if (term != null) 'term': term,
    };
  }

  factory Timetable.fromJson(Map<String, dynamic> json) {
    return Timetable(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled Timetable',
      createdAt: parseDateTime(json['createdAt']),
      updatedAt: parseDateTime(json['updatedAt']),
      campus: json['campus'] != null
          ? Campus.fromCode(json['campus'] as String)
          : Campus.hyderabad,
      availableCourses: (json['availableCourses'] as List?)
          ?.map((c) => Course.fromJson(c))
          .toList() ?? [],
      selectedSections: (json['selectedSections'] as List?)
          ?.map((s) => SelectedSection.fromJson(s))
          .toList() ?? [],
      clashWarnings: (json['clashWarnings'] as List?)
          ?.map((w) => ClashWarning.fromJson(w))
          .toList() ?? [],
      shareId: json['shareId'] as String?,
      projectCount: json['projectCount'] as int? ?? 0,
      term: json['term'] as String?,
    );
  }

  Timetable copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Campus? campus,
    List<Course>? availableCourses,
    List<SelectedSection>? selectedSections,
    List<ClashWarning>? clashWarnings,
    String? Function()? shareId,
    int? projectCount,
    String? term,
  }) {
    return Timetable(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      campus: campus ?? this.campus,
      availableCourses: availableCourses ?? this.availableCourses,
      selectedSections: selectedSections ?? this.selectedSections,
      clashWarnings: clashWarnings ?? this.clashWarnings,
      shareId: shareId != null ? shareId() : this.shareId,
      projectCount: projectCount ?? this.projectCount,
      term: term ?? this.term,
    );
  }
}

/// A user's choice of one section within a course (e.g. CS F111 → L1).
/// Carries the full [Section] data for display without a catalog lookup.
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

/// A detected scheduling conflict between two or more courses.
/// Produced by [ClashDetector.detectClashes].
class ClashWarning {
  final ClashType type;
  final String message;
  final List<String> conflictingCourses;

  /// [ClashSeverity.error] blocks the combination; [ClashSeverity.warning] is informational.
  final ClashSeverity severity;

  /// Date of the colliding paper, for exam clashes only — lets the UI state the
  /// date without parsing it back out of [message]. Null for class clashes.
  final DateTime? examDate;

  ClashWarning({
    required this.type,
    required this.message,
    required this.conflictingCourses,
    required this.severity,
    this.examDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'message': message,
      'conflictingCourses': conflictingCourses,
      'severity': severity.toString(),
      if (examDate != null) 'examDate': examDate!.toIso8601String(),
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
      examDate: json['examDate'] == null
          ? null
          : DateTime.tryParse(json['examDate'] as String),
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

/// A flattened view of one course-section occupying specific hours on a
/// single day. Used by grid/export renderers.
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

class ArchivedSemester {
  final String id;
  final String academicYear;
  final int semester;
  final DateTime archivedAt;
  final int timetableCount;

  const ArchivedSemester({
    required this.id,
    required this.academicYear,
    required this.semester,
    required this.archivedAt,
    required this.timetableCount,
  });

  String get label => '$academicYear Sem $semester';
}