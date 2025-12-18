import 'course.dart';
import 'timetable.dart';
import '../services/campus_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

export 'course.dart';
export 'timetable.dart' show Timetable, SelectedSection, TimetableSlot, ClashWarning, ClashType, ClashSeverity;

// Helper function to parse DateTime from both String and Firestore Timestamp
DateTime _parseDateTime(dynamic value) {
  if (value == null) {
    return DateTime.now();
  } else if (value is String) {
    return DateTime.parse(value);
  } else if (value is Timestamp) {
    return value.toDate();
  } else {
    return DateTime.now();
  }
}

/// Normalized timetable model that stores only references to courses
/// instead of duplicating the entire course catalog
class NormalizedTimetable {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SectionReference> selectedSections;
  final List<ClashWarning> clashWarnings;
  final String? courseVersion; // For cache invalidation

  NormalizedTimetable({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.selectedSections,
    required this.clashWarnings,
    this.courseVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedSections': selectedSections.map((s) => s.toJson()).toList(),
      'clashWarnings': clashWarnings.map((w) => w.toJson()).toList(),
      'courseVersion': courseVersion,
    };
  }

  factory NormalizedTimetable.fromJson(Map<String, dynamic> json) {
    return NormalizedTimetable(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled Timetable',
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      selectedSections: (json['selectedSections'] as List? ?? [])
          .map((s) => SectionReference.fromJson(s))
          .toList(),
      clashWarnings: (json['clashWarnings'] as List? ?? [])
          .map((w) => ClashWarning.fromJson(w))
          .toList(),
      courseVersion: json['courseVersion'],
    );
  }

  /// Convert to legacy format for backward compatibility
  Timetable toLegacyTimetable(List<Course> availableCourses) {
    final selectedSectionsLegacy = selectedSections.map((ref) {
      final course = availableCourses.firstWhere(
        (c) => c.courseCode == ref.courseCode,
        orElse: () => throw Exception('Course not found: ${ref.courseCode}'),
      );
      final section = course.sections.firstWhere(
        (s) => s.sectionId == ref.sectionId,
        orElse: () => throw Exception('Section not found: ${ref.sectionId}'),
      );
      return SelectedSection(
        courseCode: ref.courseCode,
        sectionId: ref.sectionId,
        section: section,
      );
    }).toList();

    return Timetable(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      campus: Campus.hyderabad, // Default to hyderabad for migration
      availableCourses: availableCourses,
      selectedSections: selectedSectionsLegacy,
      clashWarnings: clashWarnings,
    );
  }

  /// Create from legacy timetable
  factory NormalizedTimetable.fromLegacyTimetable(Timetable legacy) {
    final sectionRefs = legacy.selectedSections.map((selected) {
      return SectionReference(
        courseCode: selected.courseCode,
        sectionId: selected.sectionId,
      );
    }).toList();

    return NormalizedTimetable(
      id: legacy.id,
      name: legacy.name,
      createdAt: legacy.createdAt,
      updatedAt: legacy.updatedAt,
      selectedSections: sectionRefs,
      clashWarnings: legacy.clashWarnings,
    );
  }
}

/// Lightweight reference to a course section
class SectionReference {
  final String courseCode;
  final String sectionId;

  SectionReference({
    required this.courseCode,
    required this.sectionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'sectionId': sectionId,
    };
  }

  factory SectionReference.fromJson(Map<String, dynamic> json) {
    return SectionReference(
      courseCode: json['courseCode'],
      sectionId: json['sectionId'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionReference &&
          runtimeType == other.runtimeType &&
          courseCode == other.courseCode &&
          sectionId == other.sectionId;

  @override
  int get hashCode => courseCode.hashCode ^ sectionId.hashCode;

  @override
  String toString() => '$courseCode-$sectionId';
}

/// Represents incremental changes to a timetable
class TimetableUpdateBatch {
  final String timetableId;
  final List<SectionReference> sectionsToAdd;
  final List<SectionReference> sectionsToRemove;
  final Map<String, dynamic>? metadataUpdates;

  TimetableUpdateBatch({
    required this.timetableId,
    this.sectionsToAdd = const [],
    this.sectionsToRemove = const [],
    this.metadataUpdates,
  });

  Map<String, dynamic> toJson() {
    return {
      'timetableId': timetableId,
      'sectionsToAdd': sectionsToAdd.map((s) => s.toJson()).toList(),
      'sectionsToRemove': sectionsToRemove.map((s) => s.toJson()).toList(),
      'metadataUpdates': metadataUpdates,
    };
  }

  bool get isEmpty => 
      sectionsToAdd.isEmpty && 
      sectionsToRemove.isEmpty && 
      (metadataUpdates?.isEmpty ?? true);
}

/// Course metadata for version tracking
class CourseMetadata {
  final String version;
  final DateTime lastUpdated;
  final Map<String, String> courseHashes; // courseCode -> hash

  CourseMetadata({
    required this.version,
    required this.lastUpdated,
    required this.courseHashes,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'lastUpdated': lastUpdated.toIso8601String(),
      'courseHashes': courseHashes,
    };
  }

  factory CourseMetadata.fromJson(Map<String, dynamic> json) {
    return CourseMetadata(
      version: json['version'],
      lastUpdated: _parseDateTime(json['lastUpdated']),
      courseHashes: Map<String, String>.from(json['courseHashes']),
    );
  }
}