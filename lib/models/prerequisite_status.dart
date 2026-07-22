import 'academic_record.dart';
import 'prerequisite.dart';

/// A student's standing against one course's prerequisites.
///
/// The prerequisite data says what a course needs; the CGPA record says what
/// has been cleared. Pairing them turns an abstract chain into "you can take
/// this" or "you still need X".
///
/// Requirement types come from the source data as `pre` (must precede),
/// `co/pre` (may be taken alongside) and `nan` (unclear). Only `pre` can
/// actually block, so the three are kept apart rather than lumped together.
class PrerequisiteStatus {
  /// Requirements the student has already cleared.
  final List<Prerequisite> cleared;

  /// `pre` requirements not cleared — the ones that genuinely block.
  final List<Prerequisite> outstanding;

  /// `co/pre` requirements not cleared. Not blocking: they can be taken in the
  /// same semester, so they are advice rather than an obstacle.
  final List<Prerequisite> concurrent;

  /// Requirements whose type the source data doesn't pin down. Never judged
  /// either way — flagged so the student checks for themselves.
  final List<Prerequisite> unclear;

  /// The course lists alternatives, any one of which suffices (`all_one` is
  /// "one") rather than requiring the full set.
  final bool anyOneSuffices;

  /// False when the student has no CGPA record, which makes every verdict
  /// unknown rather than negative.
  final bool hasRecord;

  const PrerequisiteStatus({
    required this.cleared,
    required this.outstanding,
    required this.concurrent,
    required this.unclear,
    required this.anyOneSuffices,
    required this.hasRecord,
  });

  static const PrerequisiteStatus unknown = PrerequisiteStatus(
    cleared: [],
    outstanding: [],
    concurrent: [],
    unclear: [],
    anyOneSuffices: false,
    hasRecord: false,
  );

  bool get hasAnyRequirement =>
      cleared.isNotEmpty ||
      outstanding.isNotEmpty ||
      concurrent.isNotEmpty ||
      unclear.isNotEmpty;

  /// Null when unknowable — no record, or nothing to check.
  ///
  /// [unclear] requirements deliberately do not make this false: guessing that
  /// a student is blocked by a requirement the data cannot describe would be
  /// worse than staying quiet.
  bool? get isMet {
    if (!hasRecord || !hasAnyRequirement) return null;
    if (anyOneSuffices) return cleared.isNotEmpty;
    return outstanding.isEmpty;
  }

  static PrerequisiteStatus of(
    CoursePrerequisites course,
    AcademicRecord record,
  ) {
    if (!record.isNotEmpty || !course.hasPrerequisites) {
      return PrerequisiteStatus(
        cleared: const [],
        outstanding: const [],
        concurrent: const [],
        unclear: const [],
        anyOneSuffices: course.allOne?.toLowerCase() == 'one',
        hasRecord: record.isNotEmpty,
      );
    }

    final cleared = <Prerequisite>[];
    final outstanding = <Prerequisite>[];
    final concurrent = <Prerequisite>[];
    final unclear = <Prerequisite>[];

    for (final prereq in course.prereqs) {
      if (record.hasPassed(prereq.courseCode)) {
        cleared.add(prereq);
        continue;
      }
      switch (prereq.type.toLowerCase()) {
        case 'pre':
          outstanding.add(prereq);
        case 'co/pre':
          concurrent.add(prereq);
        default:
          unclear.add(prereq);
      }
    }

    return PrerequisiteStatus(
      cleared: cleared,
      outstanding: outstanding,
      concurrent: concurrent,
      unclear: unclear,
      anyOneSuffices: course.allOne?.toLowerCase() == 'one',
      hasRecord: true,
    );
  }
}
