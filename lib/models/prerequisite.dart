/// One acceptable course for a requirement, with its relationship type.
///
/// `type` comes from the source data: `pre` (must precede), `co/pre` (may be
/// taken alongside), `nan` (unclear).
class Prerequisite {
  final String courseCode;
  final String type;

  Prerequisite({
    required this.courseCode,
    required this.type,
  });

  factory Prerequisite.fromMap(Map<String, dynamic> map) {
    return Prerequisite(
      courseCode: map['course_code'] ?? '',
      type: canonicalType(map['type']),
    );
  }

  /// The app understands exactly `pre` / `co/pre` / `nan`. Source data uses
  /// several other spellings for co-requisites ("co", "co-req", "pre/co"); fold
  /// them onto the canonical set at the boundary so no consumer ever has to
  /// cope with an alias, whatever path the data arrived by.
  static String canonicalType(dynamic raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'pre':
        return 'pre';
      case 'co/pre':
      case 'co':
      case 'co-req':
      case 'coreq':
      case 'pre/co':
        return 'co/pre';
      case 'nan':
        return 'nan';
      default:
        return 'nan'; // unrecognised → explicitly unclear, never a wrong guess
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'course_code': courseCode,
      'type': type,
    };
  }
}

/// A single requirement. Satisfied if **any one** of its [options] is cleared —
/// the options are cross-listed equivalents (e.g. the same course offered as
/// `ECE F211` / `EEE F211` / `INSTR F211`) or genuine alternatives. Usually a
/// group has just one option. A course's requirements are the AND of all its
/// groups; the OR lives inside each group.
class PrerequisiteGroup {
  final List<Prerequisite> options;

  const PrerequisiteGroup(this.options);

  bool get isEmpty => options.isEmpty;
  bool get isNotEmpty => options.isNotEmpty;

  /// The relationship this requirement bears to the target course. Options are
  /// expected to share a type; if they differ, the most binding one wins
  /// (`pre` > `co/pre` > `nan`).
  String get type {
    if (options.any((o) => o.type.toLowerCase() == 'pre')) return 'pre';
    if (options.any((o) => o.type.toLowerCase() == 'co/pre')) return 'co/pre';
    return options.isEmpty ? 'pre' : options.first.type;
  }

  /// Human-readable list of the acceptable codes, e.g. "ECE F211 / EEE F211".
  String get label => options.map((o) => o.courseCode).join(' / ');

  factory PrerequisiteGroup.fromMap(Map<String, dynamic> map) {
    final opts = (map['options'] as List?)
            ?.map((e) => Prerequisite.fromMap(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return PrerequisiteGroup(opts);
  }

  Map<String, dynamic> toMap() => {
        'options': options.map((o) => o.toMap()).toList(),
      };
}

class CoursePrerequisites {
  final String courseCode;

  /// Requirement groups. Every group must be satisfied (AND); within a group,
  /// any one option suffices (OR).
  final List<PrerequisiteGroup> groups;
  final bool hasPrerequisites;

  const CoursePrerequisites({
    required this.courseCode,
    required this.groups,
    required this.hasPrerequisites,
  });

  /// Reads both the new grouped shape (`groups`) and the legacy flat shape
  /// (`prereqs` + `all_one`), converting the latter on the fly so the app keeps
  /// working before the data migration runs.
  factory CoursePrerequisites.fromMap(Map<String, dynamic> map) {
    final courseCode = map['course_code'] ?? '';

    if (map['groups'] != null) {
      final groups = (map['groups'] as List)
          .map((g) => PrerequisiteGroup.fromMap(g as Map<String, dynamic>))
          .where((g) => g.isNotEmpty)
          .toList();
      return CoursePrerequisites(
        courseCode: courseCode,
        groups: groups,
        hasPrerequisites: map['has_prerequisites'] ?? groups.isNotEmpty,
      );
    }

    // Legacy shape.
    final legacy = (map['prereqs'] as List?)
            ?.map((e) => Prerequisite.fromMap(e as Map<String, dynamic>))
            .toList() ??
        const <Prerequisite>[];
    final allOne = (map['all_one'] as String?)?.toLowerCase() == 'one';
    final groups = legacyToGroups(legacy, allOne: allOne);
    return CoursePrerequisites(
      courseCode: courseCode,
      groups: groups,
      hasPrerequisites: map['has_prerequisites'] ?? groups.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'course_code': courseCode,
      'groups': groups.map((g) => g.toMap()).toList(),
      'has_prerequisites': hasPrerequisites,
    };
  }

  /// Legacy → grouped conversion. A slash-joined code becomes one group of
  /// OR-options; `all_one` collapses the whole flat list into a single group.
  static List<PrerequisiteGroup> legacyToGroups(
    List<Prerequisite> legacy, {
    required bool allOne,
  }) {
    if (legacy.isEmpty) return const [];
    if (allOne) {
      return [PrerequisiteGroup(legacy.expand(_splitCrossListed).toList())];
    }
    return legacy
        .map((p) => PrerequisiteGroup(_splitCrossListed(p).toList()))
        .toList();
  }

  /// "EEE/INSTR F243" → [EEE F243, INSTR F243]; a plain code stays as-is.
  static Iterable<Prerequisite> _splitCrossListed(Prerequisite p) {
    final code = p.courseCode.trim();
    final m = RegExp(
      r'^([A-Z]{2,6}(?:/[A-Z]{2,6})+)\s+(F\d{3}[A-Z]?|G\d{3}[A-Z]?)$',
      caseSensitive: false,
    ).firstMatch(code);
    if (m == null) return [p];
    final number = m.group(2)!;
    return m
        .group(1)!
        .split('/')
        .map((dept) => Prerequisite(courseCode: '${dept.trim()} $number', type: p.type));
  }
}
