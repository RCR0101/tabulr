import '../../models/course.dart';
import '../../models/timetable.dart';
import 'clash_detector.dart';

class TimetableRepairPreferences {
  const TimetableRepairPreferences({
    this.preserveFreeDays = true,
    this.preserveInstructors = true,
    this.lockedCourseCodes = const {},
    this.maxAdditionalChanges = 2,
  });

  final bool preserveFreeDays;
  final bool preserveInstructors;
  final Set<String> lockedCourseCodes;
  final int maxAdditionalChanges;
}

class TimetableRepairChange {
  const TimetableRepairChange({
    required this.courseCode,
    required this.sectionType,
    required this.fromSectionId,
    required this.toSectionId,
    required this.fromInstructor,
    required this.toInstructor,
    required this.requested,
  });

  final String courseCode;
  final SectionType sectionType;
  final String? fromSectionId;
  final String? toSectionId;
  final String? fromInstructor;
  final String? toInstructor;
  final bool requested;

  bool get instructorChanged =>
      fromInstructor != null &&
      toInstructor != null &&
      fromInstructor != toInstructor;

  String get sectionTypeLabel => switch (sectionType) {
    SectionType.L => 'Lecture',
    SectionType.T => 'Tutorial',
    SectionType.P => 'Practical',
  };

  String get summary {
    if (fromSectionId == null) {
      return '$courseCode $sectionTypeLabel: add $toSectionId';
    }
    if (toSectionId == null) {
      return '$courseCode $sectionTypeLabel: remove $fromSectionId';
    }
    return '$courseCode $sectionTypeLabel: $fromSectionId -> $toSectionId';
  }
}

class TimetableRepairPlan {
  const TimetableRepairPlan({
    required this.newSections,
    required this.changes,
    required this.disruptionScore,
    required this.lostFreeDays,
    required this.instructorChangeCount,
  });

  final List<SelectedSection> newSections;
  final List<TimetableRepairChange> changes;
  final int disruptionScore;
  final Set<DayOfWeek> lostFreeDays;
  final int instructorChangeCount;

  List<TimetableRepairChange> get collateralChanges =>
      changes.where((change) => !change.requested).toList();

  bool get isDirect => collateralChanges.isEmpty;

  String get impactLabel {
    if (isDirect && lostFreeDays.isEmpty && instructorChangeCount == 0) {
      return 'Direct fit';
    }
    final details = <String>[];
    if (collateralChanges.isNotEmpty) {
      details.add(
        '${collateralChanges.length} collateral section '
        '${collateralChanges.length == 1 ? 'change' : 'changes'}',
      );
    }
    if (lostFreeDays.isNotEmpty) {
      details.add(
        '${lostFreeDays.length} free '
        '${lostFreeDays.length == 1 ? 'day' : 'days'} lost',
      );
    }
    if (instructorChangeCount > 0) {
      details.add(
        '$instructorChangeCount instructor '
        '${instructorChangeCount == 1 ? 'change' : 'changes'}',
      );
    }
    return details.join(' · ');
  }
}

/// Finds bounded, minimum-disruption repairs for an existing timetable.
///
/// The requested course/section change is fixed first. A breadth-first search
/// then changes at most [TimetableRepairPreferences.maxAdditionalChanges]
/// sections from other, unprotected courses to remove resulting clashes.
abstract final class TimetableRepairService {
  static const int _candidateCombinationLimit = 200;
  static const int _visitedStateLimit = 1200;

  static List<TimetableRepairPlan> planSectionRepair({
    required List<SelectedSection> currentSections,
    required List<Course> availableCourses,
    required String courseCode,
    required Set<String> unavailableSectionIds,
    TimetableRepairPreferences preferences = const TimetableRepairPreferences(),
    int maxPlans = 20,
  }) {
    final course = _courseByCode(availableCourses, courseCode);
    if (course == null || unavailableSectionIds.isEmpty) return const [];

    final affected =
        currentSections
            .where(
              (selection) =>
                  selection.courseCode == courseCode &&
                  unavailableSectionIds.contains(selection.sectionId),
            )
            .toList();
    if (affected.isEmpty) return const [];

    final options = <List<Section>>[];
    for (final selection in affected) {
      final alternatives =
          course.sections
              .where(
                (section) =>
                    section.type == selection.section.type &&
                    !unavailableSectionIds.contains(section.sectionId) &&
                    section.sectionId != selection.sectionId,
              )
              .toList();
      if (alternatives.isEmpty) return const [];
      options.add(alternatives);
    }

    final requestedKeys = {
      for (final selection in affected) _selectionKey(selection),
    };
    final seeds = <List<SelectedSection>>[];
    for (final combination in _cartesian(options)) {
      final replacements = <String, Section>{};
      for (var index = 0; index < affected.length; index++) {
        replacements[_selectionKey(affected[index])] = combination[index];
      }
      seeds.add([
        for (final selection in currentSections)
          if (replacements[_selectionKey(selection)] case final section?)
            SelectedSection(
              courseCode: selection.courseCode,
              sectionId: section.sectionId,
              section: section,
              comCode: selection.comCode,
            )
          else
            selection,
      ]);
    }

    return _planFromSeeds(
      original: currentSections,
      seeds: seeds,
      requestedKeys: requestedKeys,
      fixedCourseCodes: {courseCode},
      availableCourses: availableCourses,
      preferences: preferences,
      maxPlans: maxPlans,
    );
  }

  static List<TimetableRepairPlan> planCourseReplacement({
    required List<SelectedSection> currentSections,
    required List<Course> availableCourses,
    required String sourceCourseCode,
    required Course replacementCourse,
    required CreditBasis creditBasis,
    TimetableRepairPreferences preferences = const TimetableRepairPreferences(),
    int maxPlans = 10,
  }) {
    final source =
        currentSections
            .where((selection) => selection.courseCode == sourceCourseCode)
            .toList();
    if (source.isEmpty || !replacementCourse.offersBasis(creditBasis)) {
      return const [];
    }

    final byType = <SectionType, List<Section>>{};
    for (final section in replacementCourse.sections) {
      byType.putIfAbsent(section.type, () => []).add(section);
    }
    if (byType.isEmpty) return const [];

    final types =
        byType.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    final combinations = _cartesian([for (final type in types) byType[type]!]);
    final retained =
        currentSections
            .where((selection) => selection.courseCode != sourceCourseCode)
            .toList();
    final replacementComCode =
        replacementCourse.variantOn(creditBasis)?.comCode;
    final seeds = [
      for (final combination in combinations)
        [
          ...retained,
          for (var index = 0; index < types.length; index++)
            SelectedSection(
              courseCode: replacementCourse.courseCode,
              sectionId: combination[index].sectionId,
              section: combination[index],
              comCode: replacementComCode,
            ),
        ],
    ];

    final requestedKeys = {
      for (final selection in source) _selectionKey(selection),
      for (final type in types) '${replacementCourse.courseCode}:${type.name}',
    };

    return _planFromSeeds(
      original: currentSections,
      seeds: seeds,
      requestedKeys: requestedKeys,
      fixedCourseCodes: {replacementCourse.courseCode},
      availableCourses: availableCourses,
      preferences: preferences,
      maxPlans: maxPlans,
    );
  }

  static List<TimetableRepairPlan> _planFromSeeds({
    required List<SelectedSection> original,
    required List<List<SelectedSection>> seeds,
    required Set<String> requestedKeys,
    required Set<String> fixedCourseCodes,
    required List<Course> availableCourses,
    required TimetableRepairPreferences preferences,
    required int maxPlans,
  }) {
    final plansByState = <String, TimetableRepairPlan>{};
    final visited = <String>{};
    final queue = <_RepairState>[
      for (final seed in seeds) _RepairState(seed, 0),
    ];
    var cursor = 0;

    while (cursor < queue.length &&
        visited.length < _visitedStateLimit &&
        plansByState.length < maxPlans * 4) {
      final state = queue[cursor++];
      final stateKey = _stateKey(state.sections);
      if (!visited.add(stateKey)) continue;

      final clashes =
          ClashDetector.detectClashes(state.sections, availableCourses)
              .where((warning) => warning.severity == ClashSeverity.error)
              .toList();
      if (clashes.isEmpty) {
        plansByState[stateKey] = _buildPlan(
          original: original,
          repaired: state.sections,
          requestedKeys: requestedKeys,
          preferences: preferences,
        );
        continue;
      }
      if (state.additionalChanges >= preferences.maxAdditionalChanges) {
        continue;
      }

      final conflictingCodes = clashes
          .expand((warning) => warning.conflictingCourses)
          .toSet()
          .where(
            (code) =>
                !fixedCourseCodes.contains(code) &&
                !preferences.lockedCourseCodes.contains(code),
          );

      for (final courseCode in conflictingCodes) {
        final course = _courseByCode(availableCourses, courseCode);
        if (course == null) continue;
        for (var index = 0; index < state.sections.length; index++) {
          final current = state.sections[index];
          if (current.courseCode != courseCode) continue;
          final alternatives = course.sections.where(
            (section) =>
                section.type == current.section.type &&
                section.sectionId != current.sectionId,
          );
          for (final alternative in alternatives) {
            final next = [...state.sections];
            next[index] = SelectedSection(
              courseCode: current.courseCode,
              sectionId: alternative.sectionId,
              section: alternative,
              comCode: current.comCode,
            );
            queue.add(_RepairState(next, state.additionalChanges + 1));
          }
        }
      }
    }

    final plans =
        plansByState.values.toList()..sort((a, b) {
          final byDisruption = a.disruptionScore.compareTo(b.disruptionScore);
          if (byDisruption != 0) return byDisruption;
          return _stateKey(a.newSections).compareTo(_stateKey(b.newSections));
        });
    return plans.take(maxPlans).toList();
  }

  static TimetableRepairPlan _buildPlan({
    required List<SelectedSection> original,
    required List<SelectedSection> repaired,
    required Set<String> requestedKeys,
    required TimetableRepairPreferences preferences,
  }) {
    final before = {
      for (final selection in original) _selectionKey(selection): selection,
    };
    final after = {
      for (final selection in repaired) _selectionKey(selection): selection,
    };
    final keys = {...before.keys, ...after.keys}.toList()..sort();
    final changes = <TimetableRepairChange>[];

    for (final key in keys) {
      final oldSelection = before[key];
      final newSelection = after[key];
      if (oldSelection?.sectionId == newSelection?.sectionId) continue;
      final exemplar = newSelection ?? oldSelection!;
      changes.add(
        TimetableRepairChange(
          courseCode: exemplar.courseCode,
          sectionType: exemplar.section.type,
          fromSectionId: oldSelection?.sectionId,
          toSectionId: newSelection?.sectionId,
          fromInstructor: oldSelection?.section.instructor,
          toInstructor: newSelection?.section.instructor,
          requested: requestedKeys.contains(key),
        ),
      );
    }

    final originalFreeDays = _freeDays(original);
    final repairedFreeDays = _freeDays(repaired);
    final lostFreeDays = originalFreeDays.difference(repairedFreeDays);
    final instructorChanges =
        changes.where((change) => change.instructorChanged).length;
    final collateralCourseCount =
        changes
            .where((change) => !change.requested)
            .map((change) => change.courseCode)
            .toSet()
            .length;
    final timingDrift = _timingDrift(original, repaired);

    final score =
        collateralCourseCount * 1000 +
        changes.where((change) => !change.requested).length * 100 +
        (preferences.preserveFreeDays ? lostFreeDays.length * 250 : 0) +
        (preferences.preserveInstructors ? instructorChanges * 80 : 0) +
        timingDrift;

    return TimetableRepairPlan(
      newSections: List.unmodifiable(repaired),
      changes: List.unmodifiable(changes),
      disruptionScore: score,
      lostFreeDays: Set.unmodifiable(lostFreeDays),
      instructorChangeCount: instructorChanges,
    );
  }

  static List<List<Section>> _cartesian(List<List<Section>> options) {
    var combinations = <List<Section>>[const []];
    for (final choices in options) {
      final next = <List<Section>>[];
      for (final combination in combinations) {
        for (final choice in choices) {
          next.add([...combination, choice]);
          if (next.length >= _candidateCombinationLimit) break;
        }
        if (next.length >= _candidateCombinationLimit) break;
      }
      combinations = next;
      if (combinations.isEmpty) break;
    }
    return combinations;
  }

  static Course? _courseByCode(List<Course> courses, String code) {
    for (final course in courses) {
      if (course.courseCode == code) return course;
    }
    return null;
  }

  static String _selectionKey(SelectedSection selection) =>
      '${selection.courseCode}:${selection.section.type.name}';

  static String _stateKey(List<SelectedSection> sections) {
    final parts = [
      for (final selection in sections)
        '${_selectionKey(selection)}:${selection.sectionId}',
    ]..sort();
    return parts.join('|');
  }

  static Set<DayOfWeek> _freeDays(List<SelectedSection> sections) {
    final occupied = <DayOfWeek>{};
    for (final selection in sections) {
      for (final entry in selection.section.schedule) {
        occupied.addAll(entry.days);
      }
    }
    return DayOfWeek.values.toSet().difference(occupied);
  }

  static int _timingDrift(
    List<SelectedSection> original,
    List<SelectedSection> repaired,
  ) {
    Set<String> slots(List<SelectedSection> selections) => {
      for (final selection in selections)
        for (final entry in selection.section.schedule)
          for (final day in entry.days)
            for (final hour in entry.hours)
              '${selection.courseCode}:${day.name}:$hour',
    };
    final before = slots(original);
    final after = slots(repaired);
    return before.difference(after).length + after.difference(before).length;
  }
}

class _RepairState {
  const _RepairState(this.sections, this.additionalChanges);

  final List<SelectedSection> sections;
  final int additionalChanges;
}
