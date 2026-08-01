import 'package:flutter/material.dart';

/// The three elective pools a student picks from.
///
/// Lives here rather than on the electives screen because the same three pools
/// are a filter on any course list — the screen browses them, the advanced
/// search narrows to them, and both have to mean the same thing.
enum ElectivePool {
  discipline('Discipline', 'DEL', Icons.school_outlined),
  humanities('Humanities', 'HUEL', Icons.library_books_outlined),
  open('Open', 'OPEL', Icons.explore_outlined);

  const ElectivePool(this.label, this.short, this.icon);

  final String label;
  final String short;
  final IconData icon;

  /// Whether the pool's *contents* depend on the semester.
  ///
  /// False for Open Electives — the pool is "everything outside your
  /// requirements", which does not vary by term. The semester control stays
  /// live for it regardless, because the clash filter needs to know which CDCs
  /// you are taking, and those very much depend on the semester.
  bool get membershipVariesBySemester => this != ElectivePool.open;

  String get blurb => switch (this) {
        ElectivePool.discipline =>
          'Electives from your own discipline, filtered to what is offered '
              'this semester and does not clash with your core courses.',
        ElectivePool.humanities =>
          'The HUEL pool for your branch and semester.',
        ElectivePool.open =>
          'Every offered course outside the CDC, DEL and HUEL requirements of '
              'your branch. A DEL counts as an OPEL once your DEL requirement '
              'is met, and a HUEL once your HUEL requirement is met.',
      };
}

/// Which pools a degree's courses fall into, resolved once and then asked
/// cheaply per course.
///
/// The pools are set operations on a branch's own requirements, so they are
/// branch-relative: another discipline's core is a legitimate open elective
/// for you. Built by [BranchStructureService.electivePoolsFor].
@immutable
class ElectivePools {
  const ElectivePools({
    required this.cdcs,
    required this.dels,
    required this.huels,
  });

  static const empty = ElectivePools(cdcs: {}, dels: {}, huels: {});

  final Set<String> cdcs;
  final Set<String> dels;
  final Set<String> huels;

  /// True when no branch was known, so nothing can be classified and the filter
  /// has to stay out of the way rather than hide every course.
  bool get isEmpty => cdcs.isEmpty && dels.isEmpty && huels.isEmpty;

  /// Whether [courseCode] belongs to [pool] for this degree.
  ///
  /// Open is the strict complement of the three requirement sets, matching
  /// [OpenElectivesService]. A DEL that also counts as an OPEL once the
  /// requirement is met is not modelled — the app cannot know what a student
  /// has already cleared, and guessing would put courses in a pool they may not
  /// be allowed to take.
  bool contains(ElectivePool pool, String courseCode) => switch (pool) {
        ElectivePool.discipline => dels.contains(courseCode),
        ElectivePool.humanities => huels.contains(courseCode),
        ElectivePool.open => !cdcs.contains(courseCode) &&
            !dels.contains(courseCode) &&
            !huels.contains(courseCode),
      };

  /// Whether [courseCode] is in any of [pools]. An empty set means "no pool
  /// filter", so everything passes.
  bool matchesAny(Set<ElectivePool> pools, String courseCode) =>
      pools.isEmpty || pools.any((p) => contains(p, courseCode));
}
