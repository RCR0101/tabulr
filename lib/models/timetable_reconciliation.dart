import 'course.dart';

/// One selected section whose live catalogue entry no longer matches what the
/// student saved — either its details moved, or it is gone from the catalogue.
///
/// Produced by the load-time reconcile (see [TimetableService]) after an admin
/// re-uploads course data. A [newSection] of null means the section (or its
/// whole course) is no longer offered; the selection is kept regardless, only
/// flagged, so nothing is ever silently lost.
class SectionChange {
  SectionChange({
    required this.courseCode,
    required this.courseTitle,
    required this.sectionId,
    required this.changedFields,
    required this.oldSection,
    required this.newSection,
  });

  final String courseCode;
  final String courseTitle;
  final String sectionId;

  /// Human-readable labels for what moved, e.g. `['Room', 'Timing']`. Empty
  /// when the section was removed rather than edited.
  final List<String> changedFields;

  /// As the student had it saved.
  final Section oldSection;

  /// From the fresh catalogue, or null when it is no longer offered.
  final Section? newSection;

  bool get isRemoved => newSection == null;
}

/// The set of differences between a timetable's saved selections and the
/// catalogue just loaded. Attached transiently to the timetable during load;
/// never serialized.
class TimetableReconciliation {
  const TimetableReconciliation(this.changes);

  final List<SectionChange> changes;

  bool get hasChanges => changes.isNotEmpty;

  int get updatedCount => changes.where((c) => !c.isRemoved).length;
  int get removedCount => changes.where((c) => c.isRemoved).length;
}
