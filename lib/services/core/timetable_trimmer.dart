import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../models/timetable_constraints.dart';
import 'timetable_generator.dart';
import 'timetable_ranker.dart';

/// One way to cut an overloaded timetable down to a valid one.
class TrimOption {
  const TrimOption({
    required this.ranked,
    required this.kept,
    required this.dropped,
  });

  final RankedTimetable ranked;

  /// Course codes this option keeps, and the ones it gives up. Both are stated
  /// because what a student is really choosing between is the dropped lists —
  /// two options that keep six courses each are only comparable by which six.
  final List<String> kept;
  final List<String> dropped;

  GeneratedTimetable get timetable => ranked.timetable;
}

/// What a trim run found.
class TrimResult {
  const TrimResult({
    required this.options,
    required this.considered,
    this.impossible = const [],
    this.unmetIntents = const [],
  });

  final List<TrimOption> options;

  /// Every course code the run had to work with, pinned ones included.
  final List<String> considered;

  /// Which *required* preferences could not all hold at once, when that is why
  /// there are no options. A required intent is the student's own hard rule, so
  /// the honest answer is which rule to relax — not "nothing fits".
  final List<String> unmetIntents;

  /// Pinned courses that cannot sit together whatever else is dropped. When
  /// this is non-empty [options] is empty, and the answer is not "no timetable
  /// exists" but "these two can never both be kept".
  final List<String> impossible;
}

/// Cuts an overloaded, clashing timetable down to valid ones, ranked.
///
/// Students build a wishlist with clash bypass on and then have to work out by
/// hand which courses to give up. That is a subset-selection problem the
/// generator already solves: everything the student picked becomes an
/// *optional*, nothing is compulsory unless they pin it, and the greedy
/// insertion pass drops whatever cannot fit. [TimetableRanker] then orders the
/// survivors on the same axes the generator screen uses, so "which six" is
/// answered by exam gaps and dead hours rather than by hand.
///
/// Deliberately not a new solver: a second scorer would drift from the ranker
/// and give two different answers to the same question.
abstract final class TimetableTrimmer {
  /// [pinned] must survive every option — a course the student will not give
  /// up. [keepAtMost] caps how many of the rest come along; null fits as many
  /// as clashes and the credit cap allow.
  ///
  /// [preferences] carries the student's own tuning — gaps, free days, time of
  /// day, exam slots. Its course lists are ignored and replaced with the
  /// timetable's own, since what to trim is the whole question; everything else
  /// is passed through to the generator and the ranker untouched. Null means
  /// the defaults, which is what "assumed good" looks like.
  static Future<TrimResult> trim(
    Timetable source, {
    Set<String> pinned = const {},
    int? keepAtMost,
    TimetableConstraints? preferences,
    Map<RankAxis, AxisImportance>? importance,
    int limit = 20,
  }) async {
    final codes = <String>{
      for (final s in source.selectedSections) s.courseCode,
    }.toList();

    final pinnedInPlay = codes.where(pinned.contains).toList();
    final base = preferences ?? TimetableConstraints();
    final constraints = TimetableConstraints(
      mandatoryCourses: pinnedInPlay,
      // Order is priority order for the greedy pass; the student's own
      // selection order is the only ranking we have and is better than none.
      optionalCourses: codes.where((c) => !pinned.contains(c)).toList(),
      optionalTarget: keepAtMost == null
          ? null
          // The target counts optionals, so the pinned courses come off it
          // first — "keep 5" means five in total, not five plus the pins.
          : (keepAtMost - pinnedInPlay.length).clamp(0, codes.length),
      // The timetable's own basis wins over anything the preference panel is
      // holding: this is that timetable being trimmed, not a fresh run.
      creditBasis: source.creditBasis,
      maxCredits: base.maxCredits,
      avoidTimes: base.avoidTimes,
      avoidLabs: base.avoidLabs,
      maxHoursPerDay: base.maxHoursPerDay,
      preferredInstructors: base.preferredInstructors,
      avoidedInstructors: base.avoidedInstructors,
      avoidBackToBackClasses: base.avoidBackToBackClasses,
      instructorRankings: base.instructorRankings,
      freeDayPreference: base.freeDayPreference,
      minimizeGaps: base.minimizeGaps,
      timeOfDayPreference: base.timeOfDayPreference,
      protectLunchBreak: base.protectLunchBreak,
      earliestStartSlot: base.earliestStartSlot,
      latestEndSlot: base.latestEndSlot,
      requireHoursWindow: base.requireHoursWindow,
      requireFreeDays: base.requireFreeDays,
      requireLunchFree: base.requireLunchFree,
      preferredMidsemSlot: base.preferredMidsemSlot,
      preferredCompreSlot: base.preferredCompreSlot,
    );

    var generated = await TimetableGenerator.generateTimetables(
      source.availableCourses,
      constraints,
      maxTimetables: limit * 3,
    );

    // Required intents are hard: a week violating one is excluded outright
    // rather than ranked low. Same rule the generator screen applies, so the
    // two do not disagree about what "required" means.
    if (TimetableRanker.hasHardConstraints(constraints)) {
      final feasible = generated
          .where((tt) => TimetableRanker.meetsHardConstraints(tt, constraints))
          .toList();
      if (feasible.isEmpty) {
        return TrimResult(
          options: const [],
          considered: codes,
          unmetIntents:
              TimetableRanker.hardConflictDiagnosis(generated, constraints),
        );
      }
      generated = feasible;
    }

    if (generated.isEmpty) {
      return TrimResult(
        options: const [],
        considered: codes,
        // Only pinned courses can make a trim impossible: anything else is
        // droppable by definition, so an empty result with nothing pinned means
        // the catalogue could not place a single course.
        impossible: pinnedInPlay.length > 1
            ? _blockingPinned(source.availableCourses, constraints)
            : const [],
      );
    }

    final ranked = TimetableRanker.rank(
      generated,
      constraints,
      source.availableCourses,
      importance: importance,
    ).ranked;

    final candidates = <(RankedTimetable, Set<String>)>[];
    final seen = <String>{};
    for (final r in ranked) {
      final kept = r.timetable.sections.map((s) => s.courseCode).toSet();
      // Two options that keep the same courses differ only in section choice,
      // which is not the decision this screen is for. Keep the better-ranked.
      final key = (kept.toList()..sort()).join('|');
      if (!seen.add(key)) continue;
      candidates.add((r, kept));
    }

    // Drop any option that keeps a strict subset of another's courses. The
    // generator's leave-one-out orderings exist to vary *which* electives get
    // fitted, and they happily produce a week that gives up a course clashing
    // with nothing — a real answer when picking electives, never the answer to
    // "what do I have to give up", where it is strictly worse than the option
    // that keeps that course too.
    final options = <TrimOption>[];
    for (final (r, kept) in candidates) {
      final dominated = candidates.any((other) =>
          other.$2.length > kept.length && kept.every(other.$2.contains));
      if (dominated) continue;
      options.add(TrimOption(
        ranked: r,
        kept: codes.where(kept.contains).toList(),
        dropped: codes.where((c) => !kept.contains(c)).toList(),
      ));
      if (options.length >= limit) break;
    }

    return TrimResult(options: options, considered: codes, impossible: const []);
  }

  static List<String> _blockingPinned(
    List<Course> catalog,
    TimetableConstraints constraints,
  ) {
    final pair = TimetableGenerator.blockingPair(catalog, constraints);
    return pair == null ? const [] : [pair.$1, pair.$2];
  }

  /// Replaces [target]'s sections with the option's, in place.
  ///
  /// Goes through the caller's own add path rather than assigning, so clash
  /// warnings are rebuilt exactly as a manual edit would rebuild them.
  static List<SelectedSection> sectionsOf(TrimOption option) => [
        for (final s in option.timetable.sections)
          SelectedSection(
            courseCode: s.courseCode,
            sectionId: s.sectionId,
            section: s.section,
          ),
      ];
}
