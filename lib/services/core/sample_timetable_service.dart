import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../models/timetable_constraints.dart';
import '../data/auto_load_cdc_service.dart';
import 'timetable_generator.dart';
import 'timetable_ranker.dart';
import 'timetable_service.dart';

/// Ready-made timetables for a branch's core package: the generator run over
/// nothing but the CDCs of one semester.
///
/// It is what a student would get by opening the generator, auto-adding their
/// CDCs and pressing Generate — worth having as one tap, because that sequence
/// is most of what a first-year does on their first visit and none of it is
/// obvious the first time.
/// What a sample run found, kept apart so "this branch has no package for
/// that semester" and "the package cannot be timetabled" stay two different
/// answers — they were both an empty list, and the screen had to guess.
class SampleTimetables {
  const SampleTimetables({
    required this.codes,
    required this.samples,
    this.basis = CreditBasis.units,
    this.blocking,
  });

  /// The CDC course codes the package asked for. Empty when the branch has
  /// nothing published for that semester on this campus.
  final List<String> codes;

  /// What the package is counted in, and so what any timetable saved from these
  /// samples has to be stamped with.
  final CreditBasis basis;

  final List<RankedTimetable> samples;

  /// The two courses that clash in every combination of their sections, when
  /// that is why [samples] is empty. Null when nothing so specific was found.
  final (String, String)? blocking;

  bool get hasPackage => codes.isNotEmpty;
}

abstract final class SampleTimetableService {
  /// The best few arrangements of [semester]'s CDCs.
  ///
  /// Throws whatever [TimetableGenerator.generateTimetables] throws — an
  /// impossible package is a real answer, and the screen shows the reason.
  static Future<SampleTimetables> build({
    required String primaryBranch,
    String? secondaryBranch,
    required String semester,
    required List<Course> availableCourses,
    Set<String> chosen = const {},
    int limit = 20,
  }) async {
    final codes = await AutoLoadCDCService().loadCDCCodesForDegree(
      primaryBranch: primaryBranch,
      secondaryBranch: secondaryBranch,
      semester: semester,
      availableCourses: availableCourses,
      chosen: chosen,
    );
    if (codes.isEmpty) {
      return const SampleTimetables(codes: [], samples: []);
    }

    final basis = _basisFor(codes, availableCourses);
    final constraints = TimetableConstraints(
      mandatoryCourses: codes,
      creditBasis: basis,
    );
    final generated = await TimetableGenerator.generateTimetables(
      availableCourses,
      constraints,
      maxTimetables: limit,
    );
    final ranked = TimetableRanker.rank(generated, constraints, availableCourses)
        .ranked
        .take(limit)
        .toList();

    return SampleTimetables(
      codes: codes,
      samples: ranked,
      basis: basis,
      // Only worth the second search when there is nothing to show: it re-runs
      // the combination builder over every pair of courses.
      blocking: ranked.isEmpty
          ? TimetableGenerator.blockingPair(availableCourses, constraints)
          : null,
    );
  }

  /// What the package is counted in. A 2026 first-year package is stated in
  /// contact hours and carries 0 units, so running it on the default basis
  /// would measure the whole semester as weightless.
  static CreditBasis _basisFor(List<String> codes, List<Course> catalog) {
    final wanted = codes.toSet();
    final courses = [
      for (final c in catalog)
        if (wanted.contains(c.courseCode)) c,
    ];
    final hoursOnly = courses.any((c) =>
        c.offersBasis(CreditBasis.hours) && !c.offersBasis(CreditBasis.units));
    return hoursOnly ? CreditBasis.hours : CreditBasis.units;
  }

  /// Saves [sections] as a timetable of their own, leaving anything already
  /// open untouched. Returns the new timetable.
  ///
  /// [basis] is what the run counted in, and has to be stamped on the new
  /// timetable: the sections carry their com cods, but a timetable left on the
  /// default basis reopens filtered to the wrong half of the catalogue.
  static Future<Timetable> saveAsNew(
    List<SelectedSection> sections,
    String name, {
    CreditBasis basis = CreditBasis.units,
  }) async {
    final service = TimetableService();
    final tt = await service.createNewTimetable(
        name.trim().isEmpty ? 'Generated timetable' : name.trim(),
        creditBasis: basis);
    for (final section in sections) {
      await service.addSection(section.courseCode, section.sectionId, tt);
    }
    await service.saveTimetable(tt);
    return tt;
  }

  /// Replaces everything on [target] with [sections].
  ///
  /// [catalog] is the course list the sections were generated from, and becomes
  /// the timetable's own: a timetable built in an earlier term carries a
  /// catalog that need not contain these courses at all, and the add below
  /// resolves each section against it.
  ///
  /// Sections are added through the service rather than assigned, so the
  /// timetable's clash warnings are rebuilt exactly as they are for a manual
  /// add — an overwritten timetable that reports no clashes because nothing
  /// recomputed them would be worse than no feature.
  static Future<void> overwrite(
    Timetable target,
    List<SelectedSection> sections,
    List<Course> catalog, {
    CreditBasis basis = CreditBasis.units,
  }) async {
    final service = TimetableService();
    for (final existing in List<SelectedSection>.of(target.selectedSections)) {
      service.removeSectionWithoutSaving(
          existing.courseCode, existing.sectionId, target);
    }
    target.availableCourses
      ..clear()
      ..addAll(catalog);
    // Everything the target used to hold is gone, so its old basis is gone with
    // it — it now counts whatever the replacing sections count in.
    target.creditBasis = basis;
    for (final section in sections) {
      service.addSectionWithoutSaving(
          section.courseCode, section.sectionId, target);
    }
    await service.saveTimetable(target);
  }
}
