import 'dart:math';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../../models/credit_mix.dart';
import '../../models/timetable.dart' as timetable;
import '../../constants/app_constants.dart';
import '../../utils/datetime_utils.dart';
import 'clash_detector.dart';

/// Generates ranked timetable options from a set of courses and user preferences.
///
/// ## Pipeline
///
/// 1. **Cartesian product** — for each mandatory course, enumerate every valid
///    (L × P × T) section combination. Products are capped at 10 000 to bound
///    memory. See [_generateAllCombinations].
/// 2. **Validate** — reject any combination with a class or exam clash
///    (delegates to [ClashDetector.detectClashes]). See [_isValidCombination].
/// 3. **Greedy optional insertion** — for each surviving mandatory combo, try
///    adding optional courses one at a time (best [_comboFitness] section combo
///    wins), respecting maxCredits. Several shortlists (priority, reverse,
///    leave-one-out) are tried so the results differ in *which* optionals they
///    fit. See [_addOptionalCourses], [_generateOptionalOrderings].
/// 4. **Deduplicate** — a section-key string set prevents identical timetables
///    generated via different orderings.
/// 5. **Prune** — the pool is trimmed to [maxTimetables] by [_comboFitness], a
///    cheap internal day-shape heuristic (not user-facing), bucketed by how
///    many optionals were fitted so the emptiest weeks can't crowd out the
///    fuller ones. See [_prune].
/// 6. **Name** — each survivor gets a descriptive name. Ordering the user sees
///    is decided later by `TimetableRanker` (Pareto tiers + TOPSIS), not here.
///
/// ## Hook points
///
/// - New user-facing ranking factor: add an axis to `TimetableRanker`, not here.
/// - New generation-time heuristic: extend [_comboFitness].
/// - New section type: extend the L/P/T branching in
///   [_generateAllCombinations].
/// A partial timetable and the grid cells it has already taken.
typedef _Partial = (List<ConstraintSelectedSection>, Set<String>);

class TimetableGenerator {
  /// Entry point. Returns up to [maxTimetables] clash-free, scored timetables.
  /// How many scored candidates to evaluate before handing a frame back to the
  /// event loop. Chosen so a batch stays well under one 60fps frame (~16ms) on
  /// a mid-range phone while keeping the yield overhead negligible.
  static const int _yieldEvery = 128;

  /// Async so the UI can paint between batches. There is no isolate here on
  /// purpose: web has none, and shipping [Course]/[TimetableConstraints] across
  /// an isolate boundary would cost a full copy each way. Cooperative yielding
  /// with `Future.delayed(Duration.zero)` unblocks the UI on web and native
  /// alike — the old fully-synchronous loop froze it for seconds on large
  /// optional sets (up to the 10,000-combination cap × scoring).
  static Future<List<GeneratedTimetable>> generateTimetables(
    List<Course> availableCourses,
    TimetableConstraints constraints, {
    int maxTimetables = 30,
  }) async {
    final mandatoryCourses = availableCourses
        .where((c) => constraints.mandatoryCourses.contains(c.courseCode))
        .toList();

    if (mandatoryCourses.length != constraints.mandatoryCourses.length) {
      throw Exception('Some mandatory courses not found in available courses');
    }

    // Two mandatory courses sharing an exam slot can never produce a valid
    // combination — every candidate is rejected and the run ends in a bare "no
    // timetables found", which reads as a bug in the generator rather than a
    // clash in the offering. Name it instead.
    final examClash = _mandatoryExamClash(mandatoryCourses);
    if (examClash != null) throw Exception(examClash);

    // Chosen on the generator screen, not inferred from what happens to be
    // selected — see TimetableConstraints.creditBasis.
    final basis = constraints.creditBasis;

    // Preserve user ranking order for optionals
    final optionalCourses = constraints.optionalCourses
        .map((code) => availableCourses.firstWhere((c) => c.courseCode == code,
            orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [])))
        .where((c) => c.sections.isNotEmpty)
        // A generated timetable a student cannot register for is not a result.
        // Optionals of the other basis are dropped rather than offered and
        // then refused when they try to open one.
        .where((c) => c.offersBasis(basis))
        .toList();

    final mandatoryCombos = _generateAllCombinations(mandatoryCourses);
    final allCourses = [...mandatoryCourses, ...optionalCourses];

    final mandatoryCredits = mandatoryCourses.fold(
        0.0, (sum, c) => sum + (c.variantOn(basis)?.amount ?? 0));

    // Generate multiple optional orderings for variety
    final optionalOrderings = _generateOptionalOrderings(optionalCourses);

    final seen = <String>{};
    final validTimetables = <GeneratedTimetable>[];
    var sinceYield = 0;

    for (int i = 0; i < mandatoryCombos.length; i++) {
      final base = mandatoryCombos[i];
      if (!_isValidCombination(base, allCourses)) continue;

      for (final ordering in optionalOrderings) {
        // Hand a frame back periodically. Counting scored candidates (rather
        // than outer combos) keeps batches even when one combo has many
        // orderings.
        if (++sinceYield >= _yieldEvery) {
          sinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }

        final result = _addOptionalCourses(
          base, ordering, allCourses, constraints, mandatoryCredits, basis,
        );

        final key = (result.sections.map((s) => '${s.courseCode}:${s.sectionId}').toList()..sort()).join('|');
        if (seen.contains(key)) continue;
        seen.add(key);

        final analysis = _analyzeTimetable(result.sections, constraints, allCourses);

        if (result.optionalCodes.isNotEmpty) {
          final optNames = result.optionalCodes.join(', ');
          (analysis['pros'] as List<String>).insert(0, 'Includes optionals: $optNames');
        }

        validTimetables.add(GeneratedTimetable(
          id: '',
          sections: result.sections,
          pros: analysis['pros'] as List<String>,
          cons: analysis['cons'] as List<String>,
          hoursPerDay: _calculateHoursPerDay(result.sections),
          totalCredits: result.totalCredits,
          creditBasis: basis,
          optionalCourseCodes: result.optionalCodes,
        ));

        if (validTimetables.length >= maxTimetables * 3) break;
      }
      if (validTimetables.length >= maxTimetables * 3) break;
    }

    // Prune the pool with a cheap internal fitness (day-shape, avoided slots /
    // instructors). This is *not* the ranking the user sees — it only decides
    // which candidates advance to the intent-based ranker.
    final results = _prune(validTimetables, constraints, maxTimetables);

    // Descriptive names, assigned together so collisions can be resolved for a
    // whole group at once (see _assignNames).
    final names = _assignNames(results);
    for (int i = 0; i < results.length; i++) {
      final tt = results[i];
      results[i] = GeneratedTimetable(
        id: names[i],
        sections: tt.sections,
        pros: tt.pros,
        cons: tt.cons,
        hoursPerDay: tt.hoursPerDay,
        totalCredits: tt.totalCredits,
        creditBasis: tt.creditBasis,
        optionalCourseCodes: tt.optionalCourseCodes,
      );
    }

    return results;
  }

  /// Trims the candidate pool to [limit], keeping options that fitted more
  /// optionals in the running.
  ///
  /// [_comboFitness] measures day shape only, where every extra course can just
  /// cost more — more hours, more gaps. Sorting the whole pool by it therefore
  /// puts the *emptiest* week on top every time, and a plain `take(limit)`
  /// handed the ranker nothing but timetables that fitted no optionals at all.
  /// That is not a preference the user expressed; it is an artefact of scoring
  /// fewer courses against more.
  ///
  /// So bucket by *which* electives made it in and round-robin across the
  /// buckets, each internally ordered by fitness. Bucketing on the set rather
  /// than the count is what makes the results list offer genuinely different
  /// electives instead of thirty section-shuffles of the same two: within one
  /// count, fitness alone would keep whichever pair happened to sit best and
  /// discard every alternative pair outright.
  ///
  /// Buckets are visited largest-set-first, so the options that honour more of
  /// the request lead — but every set keeps a slot, because dropping an
  /// elective for a much better week is a trade the user is allowed to see.
  /// `TimetableRanker` decides the order actually shown.
  static List<GeneratedTimetable> _prune(
    List<GeneratedTimetable> candidates,
    TimetableConstraints constraints,
    int limit,
  ) {
    if (candidates.length <= limit) return candidates;

    final buckets = <String, List<GeneratedTimetable>>{};
    final fitness = <GeneratedTimetable, double>{};
    for (final t in candidates) {
      fitness[t] = _comboFitness(t.sections, constraints);
      final key = (t.optionalCourseCodes.toList()..sort()).join('|');
      buckets.putIfAbsent(key, () => []).add(t);
    }
    for (final bucket in buckets.values) {
      bucket.sort((a, b) => fitness[b]!.compareTo(fitness[a]!));
    }

    final order = buckets.keys.toList()
      ..sort((a, b) {
        final byCount = buckets[b]!.first.optionalCourseCodes.length
            .compareTo(buckets[a]!.first.optionalCourseCodes.length);
        if (byCount != 0) return byCount;
        return fitness[buckets[b]!.first]!.compareTo(fitness[buckets[a]!.first]!);
      });

    final results = <GeneratedTimetable>[];
    for (var depth = 0; results.length < limit; depth++) {
      var tookAny = false;
      for (final key in order) {
        final bucket = buckets[key]!;
        if (depth >= bucket.length) continue;
        results.add(bucket[depth]);
        tookAny = true;
        if (results.length >= limit) break;
      }
      if (!tookAny) break; // every bucket exhausted
    }
    return results;
  }

  /// The optional shortlists to try, each producing one candidate per mandatory
  /// combo. Their job is *subset* variety — different electives, not just
  /// different sections of the same ones.
  ///
  /// This used to rotate the list and call it "skip each optional". A rotation
  /// only changes priority, and priority only decides anything when something
  /// is blocked: greedy insertion adds every elective that fits whatever order
  /// it sees them in. So whenever they all fitted, all six orderings produced
  /// the identical set and dedupe collapsed them to one — every result offering
  /// the same electives.
  ///
  /// Leave-one-out is what actually varies the set. Capped at 6 (8 orderings
  /// total, near the old count) because the candidate pool is bounded: more
  /// orderings per mandatory combo means fewer distinct combos reach the pool,
  /// which trades away the section variety this is meant to complement.
  static List<List<Course>> _generateOptionalOrderings(List<Course> optionals) {
    if (optionals.isEmpty) return [optionals];
    // Even a single elective has two honest answers — with it, and the week you
    // get by dropping it.
    if (optionals.length == 1) return [optionals, const []];

    return [
      List.of(optionals), // the user's own priority order
      optionals.reversed.toList(),
      for (var skip = 0; skip < optionals.length && skip < 6; skip++)
        [
          for (var i = 0; i < optionals.length; i++)
            if (i != skip) optionals[i],
        ],
    ];
  }

  // Saturday is off for virtually every BITS timetable, so "Sat off" describes
  // nothing and can't tell two options apart. Only Mon–Fri freedom is notable.
  static const _weekdays = {DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F};

  /// Traits of the week this timetable produces, most distinctive first.
  static List<String> _shapeTags(GeneratedTimetable tt) {
    final freeWeekdays = tt.hoursPerDay.entries
        .where((e) => _weekdays.contains(e.key) && e.value == 0)
        .map((e) => e.key)
        .toList();
    final daysWithClasses = tt.hoursPerDay.values.where((h) => h > 0).length;
    final maxH = tt.hoursPerDay.values.fold(0, max);

    // Earliest / latest occupied slot across the week (slot 1 = 8 AM, 6 = 1 PM).
    final allSlots = _getSlotsPerDay(tt.sections).values.expand((s) => s).toList();
    final earliest = allSlots.isEmpty ? 0 : allSlots.reduce(min);
    final latest = allSlots.isEmpty ? 0 : allSlots.reduce(max);

    final tags = <String>[];

    if (freeWeekdays.length >= 2) {
      tags.add('$daysWithClasses-day week');
    } else if (freeWeekdays.length == 1) {
      tags.add('${getDayName(freeWeekdays.first, abbreviated: true)} off');
    }

    if (earliest >= 3) {
      tags.add('late starts');
    } else if (earliest >= 2) {
      tags.add('no 8 AMs');
    }

    if (latest > 0 && latest <= 6) {
      tags.add('afternoons free');
    }

    if (maxH > 0 && maxH <= 4) {
      tags.add('light days');
    } else if (maxH >= 8) {
      tags.add('packed');
    }

    if (tt.optionalCourseCodes.isNotEmpty) {
      tags.add('+${tt.optionalCourseCodes.length} elective${tt.optionalCourseCodes.length > 1 ? 's' : ''}');
    }

    if (tags.isEmpty) tags.add('balanced');
    return tags;
  }

  /// The sections one option picked for one course, sorted.
  static List<String> _sectionIdsFor(GeneratedTimetable tt, String courseCode) {
    return tt.sections
        .where((s) => s.courseCode == courseCode)
        .map((s) => s.sectionId)
        .toList()
      ..sort();
  }

  /// Per-course descriptors of what makes each option in [group] different,
  /// keyed by option index — e.g. `{0: ['CS F111 L1', 'EEE F111 L2'], ...}`.
  ///
  /// Compares each course's *set* of chosen sections across the group. A flat
  /// set of section ids would misread a course that simply has several
  /// components — a lecture AND a tutorial — as one whose choice varies.
  /// Components common to every option are dropped: a tutorial that is the same
  /// in all of them lengthens every name equally and distinguishes nothing.
  static Map<int, List<String>> _distinguishingPicks(
    List<int> group,
    List<GeneratedTimetable> results,
  ) {
    final codes = {
      for (final i in group)
        for (final s in results[i].sections) s.courseCode,
    };

    final picks = {for (final i in group) i: <String>[]};
    for (final code in codes.toList()..sort()) {
      final perOption = {
        for (final i in group) i: _sectionIdsFor(results[i], code),
      };
      if (perOption.values.map((ids) => ids.join('+')).toSet().length == 1) {
        continue; // identical in every option — says nothing
      }
      final common = perOption.values
          .map((ids) => ids.toSet())
          .reduce((a, b) => a.intersection(b));
      for (final i in group) {
        final differing = perOption[i]!.where((id) => !common.contains(id));
        for (final id in differing) {
          picks[i]!.add('$code $id');
        }
      }
    }
    return picks;
  }

  /// Names every option in one pass.
  ///
  /// One pass rather than one-at-a-time because a collision is a property of a
  /// *set* of options: naming them in sequence let the first keep the plain
  /// shape label while the rest were pushed onto a fallback, so a group that
  /// differs only by section read as "Balanced", "Option 2", "Option 3".
  ///
  /// Sections of a course usually occupy the same slots, so options frequently
  /// share an identical week shape and shape tags alone cannot separate them.
  /// When that happens the section choice IS the difference, and naming it is
  /// both honest and actionable. Nothing falls back to a bare index: the index
  /// said nothing about the timetable, and — because the ranker reorders after
  /// naming — did not even match the position the card appeared in.
  static List<String> _assignNames(List<GeneratedTimetable> results) {
    final tags = [for (final tt in results) _shapeTags(tt)];

    final byLabel = <String, List<int>>{};
    for (var i = 0; i < results.length; i++) {
      (byLabel[tags[i].take(2).join(', ')] ??= []).add(i);
    }

    final names = List<String>.filled(results.length, '');
    for (final entry in byLabel.entries) {
      final group = entry.value;
      if (group.length == 1) {
        names[group.first] = entry.key;
        continue;
      }

      // Widening to every shape tag separates some groups on its own.
      final widened = {for (final i in group) i: tags[i].join(', ')};
      if (widened.values.toSet().length == group.length) {
        for (final i in group) {
          names[i] = widened[i]!;
        }
        continue;
      }

      // Same week shape — name them by the sections that actually differ. Two
      // are usually enough to read at a glance; widening to all of them is
      // guaranteed to separate the group, since options with an identical
      // section set were already deduplicated when the pool was built.
      //
      // "balanced" means "nothing notable about the shape", so it is dropped
      // once there is something concrete to say instead.
      final picks = _distinguishingPicks(group, results);
      final maxPicks = picks.values.fold(0, (m, p) => p.length > m ? p.length : m);
      final prefix = entry.key == 'balanced' ? <String>[] : [entry.key];

      for (final limit in {2, maxPicks}) {
        final candidate = {
          for (final i in group)
            i: [...prefix, ...picks[i]!.take(limit)].join(', '),
        };
        final unique = candidate.values.toSet().length == group.length;
        if (unique || limit == maxPicks) {
          for (final i in group) {
            names[i] = candidate[i]!;
          }
          if (unique) break;
        }
      }
    }

    return [
      for (final n in names)
        n.isEmpty ? 'Balanced' : '${n[0].toUpperCase()}${n.substring(1)}',
    ];
  }

  static _OptionalResult _addOptionalCourses(
    List<ConstraintSelectedSection> base,
    List<Course> optionalCourses,
    List<Course> allCourses,
    TimetableConstraints constraints,
    double mandatoryCredits,
    CreditBasis basis,
  ) {
    var current = List<ConstraintSelectedSection>.from(base);
    double currentCredits = mandatoryCredits;
    final addedCodes = <String>{};

    for (final optCourse in optionalCourses) {
      // "Any N of M": stop once the requested number of optionals is in.
      if (constraints.optionalTarget != null && addedCodes.length >= constraints.optionalTarget!) break;
      // Measured on the run's own basis: an hours course has no unit count, so
      // reading totalCredits here would score every one of them as free.
      final optAmount = optCourse.variantOn(basis)?.amount ?? 0;
      // The caller's ceiling wins when it set one; otherwise the published cap
      // for this basis. Applied to both bases — skipping the check on hours let
      // a 2026 run pack a timetable past 70 contact hours.
      final cap = constraints.maxCredits ?? capFor(basis);
      if (currentCredits + optAmount > cap) continue;

      final sectionCombos = _generateAllCombinations([optCourse]);
      List<ConstraintSelectedSection>? bestCombo;
      // Must be -infinity, not -1. [_comboFitness] scores the *whole* timetable
      // and is almost always negative (one gap hour already costs 1), so a -1
      // sentinel silently rejected every section of every optional on any week
      // that wasn't perfectly packed — the generator looked like it was
      // "choosing" not to fit optionals when it had never considered them.
      double bestScore = double.negativeInfinity;

      for (final combo in sectionCombos) {
        final candidate = [...current, ...combo];
        if (!_isValidCombination(candidate, allCourses)) continue;

        final score = _comboFitness(candidate, constraints);
        if (score > bestScore) {
          bestScore = score;
          bestCombo = combo;
        }
      }

      if (bestCombo != null) {
        current = [...current, ...bestCombo];
        currentCredits += optAmount;
        addedCodes.add(optCourse.courseCode);
      }
    }

    return _OptionalResult(
      sections: current,
      totalCredits: currentCredits,
      optionalCodes: addedCodes,
    );
  }

  /// The grid cells a section occupies, as `"day_hour"` keys.
  static Set<String> _cells(Section section) {
    final cells = <String>{};
    for (final entry in section.schedule) {
      for (final day in entry.days) {
        for (final hour in entry.hours) {
          cells.add('${day}_$hour');
        }
      }
    }
    return cells;
  }

  /// One course's own L × P × T choices, each with the cells it occupies.
  ///
  /// A component whose sections are all unscheduled contributes nothing, which
  /// leaves the course unplaceable — same outcome as before, when such a
  /// section made every combination containing it invalid.
  static List<_Partial> _courseChoices(Course course) {
    final byType = <SectionType, List<Section>>{};
    for (final section in course.sections) {
      (byType[section.type] ??= []).add(section);
    }

    var combos = <_Partial>[(const [], const {})];
    for (final type in SectionType.values) {
      final sections = byType[type];
      if (sections == null) continue;

      final next = <_Partial>[];
      for (final (picked, occupied) in combos) {
        for (final section in sections) {
          final cells = _cells(section);
          if (cells.isEmpty) continue; // no scheduled time — nothing to place
          if (cells.any(occupied.contains)) continue; // L and P of the same course collide
          next.add((
            [
              ...picked,
              ConstraintSelectedSection(
                courseCode: course.courseCode,
                sectionId: section.sectionId,
                section: section,
              ),
            ],
            {...occupied, ...cells},
          ));
        }
      }
      if (next.isEmpty) return const [];
      combos = next;
    }

    return combos.first.$1.isEmpty ? const [] : combos;
  }

  static List<List<ConstraintSelectedSection>> _generateAllCombinations(List<Course> courses) {
    // One way to place nothing — the empty combination — not zero ways. The
    // difference matters only for the mandatory list: returning [] there made
    // the outer loop skip every ordering, so a run with nothing compulsory and
    // a pile of optionals (which is what trimming an overloaded timetable is)
    // came back empty. `choices.isEmpty` below is the genuine "no combinations"
    // case and still returns [].
    if (courses.isEmpty) return [const []];

    var partials = <_Partial>[(const [], const {})];

    for (final course in courses) {
      final choices = _courseChoices(course);
      if (choices.isEmpty) return []; // course cannot be placed at all

      final next = <_Partial>[];
      for (final (sections, occupied) in partials) {
        for (final (add, cells) in choices) {
          // Clashing partials are dropped here rather than at the end. The cap
          // below discards whatever doesn't fit, so a partial that can never
          // become a timetable would otherwise take a slot from one that can —
          // which is how a whole first-year package (six courses, ten lab
          // sections each) came back with nothing: every survivor of the cap
          // still carried the same clashing lecture from the first course.
          if (cells.any(occupied.contains)) continue;
          next.add(([...sections, ...add], {...occupied, ...cells}));
        }
      }

      if (next.isEmpty) return []; // nothing clash-free left to build on
      partials = next.length > AppLimits.combinationCap
          ? _thin(next, AppLimits.combinationCap)
          : next;
    }

    return [for (final (sections, _) in partials) sections];
  }

  /// [limit] items spread evenly across [items], rather than the first [limit].
  ///
  /// The product is built in order, so taking the front pins the courses added
  /// earliest to their first few sections — the later ones absorb the whole
  /// cut. A stride keeps every course's choices represented.
  ///
  /// ponytail: even sampling, not search. If a package ever needs a specific
  /// rare combination that the stride misses, this wants a real constraint
  /// solver, not a bigger cap.
  static List<T> _thin<T>(List<T> items, int limit) {
    final step = items.length / limit;
    return [for (var i = 0; i < limit; i++) items[(i * step).floor()]];
  }

  /// The first pair of mandatory courses that cannot share a week, whichever
  /// sections are picked — or null when the block is elsewhere.
  ///
  /// Only worth asking once a run has come back empty: it re-places every pair.
  /// "No valid timetables found" is true but useless when the cause is two
  /// courses that BITS scheduled on top of each other, which a first-year
  /// package can genuinely be.
  static (String, String)? blockingPair(
    List<Course> availableCourses,
    TimetableConstraints constraints,
  ) {
    final mandatory = availableCourses
        .where((c) => constraints.mandatoryCourses.contains(c.courseCode))
        .toList();
    for (var i = 0; i < mandatory.length; i++) {
      for (var j = i + 1; j < mandatory.length; j++) {
        if (_generateAllCombinations([mandatory[i], mandatory[j]]).isEmpty) {
          return (mandatory[i].courseCode, mandatory[j].courseCode);
        }
      }
    }
    return null;
  }

  /// The first pair of [courses] whose midsems or compres collide, phrased for
  /// the student, or null when the set is examinable as a whole.
  static String? _mandatoryExamClash(List<Course> courses) {
    final exams = <String, ExamSchedule? Function(Course)>{
      'Midsem': (c) => c.midSemExam,
      'Compre': (c) => c.endSemExam,
    };
    for (final kind in exams.entries) {
      final seen = <String, String>{};
      for (final course in courses) {
        final exam = kind.value(course);
        if (exam == null) continue;
        final key = '${exam.date.toIso8601String()}_${exam.timeSlot}';
        final other = seen[key];
        if (other != null) {
          return '${kind.key} clash: ${course.courseCode} and $other sit in the '
              'same exam slot, so no timetable can hold both. Make one optional '
              'or drop it.';
        }
        seen[key] = course.courseCode;
      }
    }
    return null;
  }

  static bool _isValidCombination(List<ConstraintSelectedSection> sections, List<Course> courses) {
    // Basic validation - check if sections have valid time slots
    for (final section in sections) {
      if (section.section.days.isEmpty || section.section.hours.isEmpty) {
        return false; // Invalid section with no scheduled time
      }
    }
    
    // Convert to timetable.dart SelectedSection for clash detection
    try {
      final timetableSections = sections.map((s) => timetable.SelectedSection(
        courseCode: s.courseCode,
        sectionId: s.sectionId,
        section: s.section,
      )).toList();
      
      final clashes = ClashDetector.detectClashes(timetableSections, courses);
      // Reject ANY clashes (both warnings and errors) to prevent conflict timetables
      final isValid = clashes.isEmpty;
      
      return isValid;
    } catch (e) {
      
      return false;
    }
  }

  /// Cheap internal fitness used only to pick a section combo and prune the
  /// candidate pool — never shown to the user (the ranker owns what they see).
  /// Higher is better: penalises long days, gaps, avoided slots/instructors,
  /// and out-of-window / lunch classes; rewards preferred instructors.
  static double _comboFitness(List<ConstraintSelectedSection> sections, TimetableConstraints c) {
    final hoursPerDay = _calculateHoursPerDay(sections);
    var penalty = 0.0;
    for (final h in hoursPerDay.values) {
      if (h > c.maxHoursPerDay) penalty += (h - c.maxHoursPerDay) * 5;
    }
    penalty += _calculateGapPenalty(_getSlotsPerDay(sections));

    for (final s in sections) {
      for (final entry in s.section.schedule) {
        final days = entry.days.length;
        for (final h in entry.hours) {
          if (c.earliestStartSlot != null && h < c.earliestStartSlot!) penalty += 3 * days;
          if (c.latestEndSlot != null && h > c.latestEndSlot!) penalty += 3 * days;
          if (c.protectLunchBreak && ScheduleConstants.lunchHours.contains(h)) {
            penalty += 1.5 * days;
          }
        }
      }
      if (c.avoidedInstructors.contains(s.section.instructor)) penalty += 15;
    }
    for (final avoid in c.avoidTimes) {
      for (final s in sections) {
        for (final entry in s.section.schedule) {
          if (entry.days.contains(avoid.day)) {
            penalty += entry.hours.where((h) => avoid.hours.contains(h)).length * 5;
          }
        }
      }
    }

    var bonus = 0.0;
    for (final s in sections) {
      if (c.preferredInstructors.contains(s.section.instructor)) bonus += 2;
    }
    return bonus - penalty;
  }

  static Map<DayOfWeek, List<int>> _getSlotsPerDay(List<ConstraintSelectedSection> sections) {
    final slots = <DayOfWeek, Set<int>>{};
    for (final day in DayOfWeek.values) {
      slots[day] = {};
    }
    for (final section in sections) {
      for (final entry in section.section.schedule) {
        for (final day in entry.days) {
          slots[day]!.addAll(entry.hours);
        }
      }
    }
    return slots.map((k, v) {
      final sorted = v.toList()..sort();
      return MapEntry(k, sorted);
    });
  }

  static double _calculateGapPenalty(Map<DayOfWeek, List<int>> slotsPerDay) {
    double totalGaps = 0;
    for (final slots in slotsPerDay.values) {
      if (slots.length < 2) continue;
      for (int i = 1; i < slots.length; i++) {
        final gap = slots[i] - slots[i - 1] - 1;
        if (gap > 0) totalGaps += gap;
      }
    }
    return totalGaps * 1.5;
  }

  static Map<String, dynamic> _analyzeTimetable(List<ConstraintSelectedSection> sections, TimetableConstraints constraints, List<Course> courses) {
    final pros = <String>[];
    final cons = <String>[];

    final hoursPerDay = _calculateHoursPerDay(sections);
    final slotsPerDay = _getSlotsPerDay(sections);
    final maxHours = hoursPerDay.values.reduce(max);
    final minHours = hoursPerDay.values.where((h) => h > 0).reduce(min);

    // Schedule distribution
    if (maxHours <= constraints.maxHoursPerDay) {
      pros.add('Within ${constraints.maxHoursPerDay}h/day limit');
    } else {
      cons.add('Exceeds max hours on some days');
    }

    if (maxHours - minHours <= 2) {
      pros.add('Well-balanced daily load');
    }

    // Preferred instructors
    final preferredCount = sections
        .where((s) => constraints.preferredInstructors.contains(s.section.instructor))
        .length;
    if (preferredCount > 0) {
      pros.add('$preferredCount preferred instructor(s)');
    }

    // Time conflicts
    bool hasConflicts = false;
    for (final avoidTime in constraints.avoidTimes) {
      for (final section in sections) {
        for (final scheduleEntry in section.section.schedule) {
          if (scheduleEntry.days.contains(avoidTime.day) &&
              scheduleEntry.hours.any((hour) => avoidTime.hours.contains(hour))) {
            hasConflicts = true;
            break;
          }
        }
        if (hasConflicts) break;
      }
      if (hasConflicts) break;
    }
    if (!hasConflicts && constraints.avoidTimes.isNotEmpty) {
      pros.add('Avoids all blocked time slots');
    } else if (hasConflicts) {
      cons.add('Conflicts with blocked time slots');
    }

    // Lab conflicts
    bool hasLabConflicts = false;
    for (final avoidLab in constraints.avoidLabs) {
      for (final section in sections) {
        if (section.section.type == SectionType.P) {
          for (final scheduleEntry in section.section.schedule) {
            if (scheduleEntry.days.contains(avoidLab.day) &&
                scheduleEntry.hours.any((hour) => avoidLab.hours.contains(hour))) {
              hasLabConflicts = true;
              break;
            }
          }
        }
        if (hasLabConflicts) break;
      }
      if (hasLabConflicts) break;
    }
    if (!hasLabConflicts && constraints.avoidLabs.isNotEmpty) {
      pros.add('Avoids all blocked lab slots');
    } else if (hasLabConflicts) {
      cons.add('Lab conflicts with blocked slots');
    }

    // Free days
    final freeDays = hoursPerDay.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toSet();
    final daysWithClasses = hoursPerDay.values.where((hours) => hours > 0).length;

    if (constraints.freeDayPreference.isNotEmpty) {
      final matchedFreeDays = constraints.freeDayPreference
          .where((d) => freeDays.contains(d))
          .map((d) => getDayName(d, abbreviated: true))
          .toList();
      if (matchedFreeDays.isNotEmpty) {
        pros.add('Free on ${matchedFreeDays.join(', ')}');
      }
      final topPref = constraints.freeDayPreference.first;
      if (!freeDays.contains(topPref)) {
        cons.add('${getDayName(topPref, abbreviated: true)} is not free');
      }
    } else if (daysWithClasses <= 4) {
      pros.add('Compact schedule ($daysWithClasses days)');
    }

    // Gaps
    if (constraints.minimizeGaps) {
      final gapPenalty = _calculateGapPenalty(slotsPerDay);
      if (gapPenalty == 0) {
        pros.add('No idle gaps between classes');
      } else if (gapPenalty > 4) {
        cons.add('Long gaps between classes');
      }
    }

    // Lunch break
    if (constraints.protectLunchBreak) {
      bool lunchFree = true;
      for (final section in sections) {
        for (final entry in section.section.schedule) {
          if (entry.hours.any(ScheduleConstants.lunchHours.contains)) {
            lunchFree = false;
            break;
          }
        }
        if (!lunchFree) break;
      }
      if (lunchFree) {
        pros.add('Lunch break is free');
      } else {
        cons.add('Classes during lunch hours');
      }
    }

    // Time of day
    if (constraints.timeOfDayPreference == TimeOfDayPreference.morning) {
      final lateCount = sections.expand((s) => s.section.schedule)
          .expand((e) => e.hours)
          .where((h) => h >= 7)
          .length;
      if (lateCount == 0) {
        pros.add('All classes in the morning');
      } else {
        cons.add('$lateCount slot(s) in the afternoon');
      }
    } else if (constraints.timeOfDayPreference == TimeOfDayPreference.afternoon) {
      final earlyCount = sections.expand((s) => s.section.schedule)
          .expand((e) => e.hours)
          .where((h) => h <= 4)
          .length;
      if (earlyCount == 0) {
        pros.add('All classes in the afternoon');
      } else {
        cons.add('$earlyCount slot(s) in the morning');
      }
    }

    // Compre exam spread (midsems are too crammed to be useful here)
    final courseCodes = sections.map((s) => s.courseCode).toSet();
    final compreDates = <DateTime>[];
    for (final code in courseCodes) {
      final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
        courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
      ));
      if (course.endSemExam != null) compreDates.add(course.endSemExam!.date);
    }
    if (compreDates.length >= 2) {
      compreDates.sort();
      bool sameDay = false;
      bool backToBack = false;
      for (int i = 1; i < compreDates.length; i++) {
        final diff = compreDates[i].difference(compreDates[i - 1]).inDays;
        if (diff == 0) sameDay = true;
        if (diff == 1) backToBack = true;
      }
      if (sameDay) {
        cons.add('Multiple compres on the same day');
      } else if (backToBack) {
        cons.add('Back-to-back compre days');
      } else {
        pros.add('Compres are well-spaced');
      }
    }

    // Exam slot preference
    if (constraints.preferredMidsemSlot != null || constraints.preferredCompreSlot != null) {
      int matched = 0;
      int total = 0;
      for (final code in courseCodes) {
        final course = courses.firstWhere((c) => c.courseCode == code, orElse: () => Course(
          courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: [],
        ));
        if (constraints.preferredMidsemSlot != null && course.midSemExam != null) {
          total++;
          if (course.midSemExam!.timeSlot == constraints.preferredMidsemSlot) matched++;
        }
        if (constraints.preferredCompreSlot != null && course.endSemExam != null) {
          total++;
          if (course.endSemExam!.timeSlot == constraints.preferredCompreSlot) matched++;
        }
      }
      if (total > 0) {
        if (matched == total) {
          pros.add('All exams in preferred slots');
        } else if (matched > 0) {
          pros.add('$matched/$total exams in preferred slots');
        } else {
          cons.add('No exams in preferred slots');
        }
      }
    }

    return {'pros': pros, 'cons': cons};
  }

  static Map<DayOfWeek, int> _calculateHoursPerDay(List<ConstraintSelectedSection> sections) {
    final hoursPerDay = <DayOfWeek, int>{};
    
    for (final day in DayOfWeek.values) {
      hoursPerDay[day] = 0;
    }

    for (final section in sections) {
      for (final scheduleEntry in section.section.schedule) {
        for (final day in scheduleEntry.days) {
          hoursPerDay[day] = hoursPerDay[day]! + scheduleEntry.hours.length;
        }
      }
    }

    return hoursPerDay;
  }
}

class _OptionalResult {
  final List<ConstraintSelectedSection> sections;
  final double totalCredits;
  final Set<String> optionalCodes;

  _OptionalResult({
    required this.sections,
    required this.totalCredits,
    required this.optionalCodes,
  });
}