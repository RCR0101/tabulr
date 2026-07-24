import 'academic_record.dart';
import 'prerequisite.dart';

/// A student's standing against one course's prerequisite groups.
///
/// The prerequisite data says what a course needs (a set of AND-ed groups, each
/// an OR of acceptable courses); the CGPA record says what has been cleared.
/// Pairing them turns an abstract chain into "you can take this" or "you still
/// need X".
///
/// A group is *cleared* when any one of its options has been passed. Requirement
/// types come from the source as `pre` (must precede), `co/pre` (may be taken
/// alongside) and `nan` (unclear); only `pre` can actually block, so the buckets
/// are kept apart rather than lumped together.
class PrerequisiteStatus {
  /// Groups the student has satisfied (at least one option cleared).
  final List<PrerequisiteGroup> cleared;

  /// `pre` groups not yet satisfied — the ones that genuinely block.
  final List<PrerequisiteGroup> outstanding;

  /// `co/pre` groups not satisfied. Not blocking: they can be taken in the same
  /// semester, so they are advice rather than an obstacle.
  final List<PrerequisiteGroup> concurrent;

  /// Groups whose type the source data doesn't pin down. Never judged either
  /// way — surfaced so the student checks for themselves.
  final List<PrerequisiteGroup> unclear;

  /// False when the student has no CGPA record, which makes every verdict
  /// unknown rather than negative.
  final bool hasRecord;

  const PrerequisiteStatus({
    required this.cleared,
    required this.outstanding,
    required this.concurrent,
    required this.unclear,
    required this.hasRecord,
  });

  static const PrerequisiteStatus unknown = PrerequisiteStatus(
    cleared: [],
    outstanding: [],
    concurrent: [],
    unclear: [],
    hasRecord: false,
  );

  bool get hasAnyRequirement =>
      cleared.isNotEmpty ||
      outstanding.isNotEmpty ||
      concurrent.isNotEmpty ||
      unclear.isNotEmpty;

  /// Null when unknowable — no record, or nothing to check.
  ///
  /// [unclear] groups deliberately do not make this false: guessing that a
  /// student is blocked by a requirement the data cannot describe would be worse
  /// than staying quiet.
  bool? get isMet {
    if (!hasRecord || !hasAnyRequirement) return null;
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
        hasRecord: record.isNotEmpty,
      );
    }

    final cleared = <PrerequisiteGroup>[];
    final outstanding = <PrerequisiteGroup>[];
    final concurrent = <PrerequisiteGroup>[];
    final unclear = <PrerequisiteGroup>[];

    for (final group in course.groups) {
      if (group.isEmpty) continue;
      // A group is satisfied if the student passed any one of its options.
      if (group.options.any((o) => record.hasPassed(o.courseCode))) {
        cleared.add(group);
        continue;
      }
      switch (group.type.toLowerCase()) {
        case 'pre':
          outstanding.add(group);
        case 'co/pre':
          concurrent.add(group);
        default:
          unclear.add(group);
      }
    }

    return PrerequisiteStatus(
      cleared: cleared,
      outstanding: outstanding,
      concurrent: concurrent,
      unclear: unclear,
      hasRecord: true,
    );
  }
}
