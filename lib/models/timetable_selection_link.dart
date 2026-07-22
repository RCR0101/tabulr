import 'package:flutter/foundation.dart';
import 'course.dart';
import 'timetable.dart';

/// Lets a browser screen pushed on top of the editor (Discipline Electives,
/// Humanities Electives) add sections straight to the timetable the user came
/// from, without owning or copying that timetable.
///
/// [selectedSections] is the editor's live list rather than a snapshot, so
/// reading it during build always reflects the current selection. [revision]
/// fires whenever that list changes, which covers the changes the browser did
/// not initiate itself — notably accepting an exam-clash Override from a toast.
///
/// A null link means "no timetable open", which leaves those screens read-only.
class TimetableSelectionLink {
  final List<SelectedSection> selectedSections;

  /// The timetable's own embedded catalog. Browsers filter against this rather
  /// than re-fetching the current one: a timetable built in a past term carries
  /// a different course list, and offering a course it cannot accept would only
  /// fail on Add.
  final List<Course> availableCourses;

  /// Called with the section's current state; the editor decides whether that
  /// means add or remove, and may refuse (clashes, credit cap).
  final void Function(String courseCode, String sectionId, bool isSelected)
      onSectionToggle;

  final Listenable revision;

  /// Shown in the browser so it's clear which timetable is being edited.
  final String timetableName;

  const TimetableSelectionLink({
    required this.selectedSections,
    required this.availableCourses,
    required this.onSectionToggle,
    required this.revision,
    required this.timetableName,
  });
}
