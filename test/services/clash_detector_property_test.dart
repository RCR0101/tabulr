import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/clash_detector.dart';
import '../helpers/test_reporter.dart';

/// Property / metamorphic stress tests for [ClashDetector].
///
/// Rather than pinning specific inputs to specific outputs (that is what
/// clash_detector_test.dart does), these run hundreds of randomised timetables
/// and assert *invariants* that must hold for every one of them, checked
/// against an independent brute-force oracle. Each property re-derives its
/// random cases from a fixed seed, so a failure is reproducible: the seed and
/// the offending selection are printed in the failure message.
void main() {
  final results = <Map<String, dynamic>>[];
  void record(String name, bool passed, int ms, [String? error]) {
    results.add({
      'name': name,
      'status': passed ? 'pass' : 'fail',
      'duration_ms': ms,
      if (error != null) 'error': error,
    });
  }

  tearDownAll(() async {
    await TestReporter.reportTestResults('clash_detector_property', results);
  });

  // Runs [body] over [trials] random selections and records timing; rethrows
  // (with the seed already embedded by the body) so the test fails loudly.
  void property(String name, void Function(int trial, Random r) body,
      {int trials = 500}) {
    test(name, () {
      final sw = Stopwatch()..start();
      try {
        for (var i = 0; i < trials; i++) {
          body(i, Random(0x5EED + i));
        }
        sw.stop();
        record(name, true, sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        record(name, false, sw.elapsedMilliseconds, e.toString());
        rethrow;
      }
    });
  }

  group('ClashDetector invariants', () {
    property('regular-class clash iff two sections share a day+hour slot',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final warnings = ClashDetector.detectClashes(selection, catalog);
      final hasClassWarning =
          warnings.any((w) => w.type == ClashType.regularClass);
      final oracle = _anyPairSharesSlot(selection);

      expect(hasClassWarning, oracle,
          reason: 'seed=${0x5EED + trial} '
              'detector=$hasClassWarning oracle=$oracle\n'
              '${_describe(selection)}');
    });

    property('one regular-class warning per over-booked grid cell',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final classWarnings = ClashDetector.detectClashes(selection, catalog)
          .where((w) => w.type == ClashType.regularClass)
          .length;

      expect(classWarnings, _overbookedCells(selection),
          reason: 'seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('exam-clash warnings match same-day/same-slot course groups',
        (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);
      final byCode = {for (final c in catalog) c.courseCode: c};

      final warnings = ClashDetector.detectClashes(selection, catalog);
      final mid =
          warnings.where((w) => w.type == ClashType.midSemExam).length;
      final end =
          warnings.where((w) => w.type == ClashType.endSemExam).length;

      expect(mid, _examClashGroups(selection, byCode, isMid: true),
          reason: 'midsem seed=${0x5EED + trial}\n${_describe(selection)}');
      expect(end, _examClashGroups(selection, byCode, isMid: false),
          reason: 'endsem seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('detectClashes is order-independent', (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);
      final shuffled = [...selection]..shuffle(r);

      final a = _signature(ClashDetector.detectClashes(selection, catalog));
      final b = _signature(ClashDetector.detectClashes(shuffled, catalog));

      expect(b, a,
          reason: 'seed=${0x5EED + trial}\n${_describe(selection)}');
    });

    property('detectClashes is deterministic (pure)', (trial, r) {
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final a = _signature(ClashDetector.detectClashes(selection, catalog));
      final b = _signature(ClashDetector.detectClashes(selection, catalog));

      expect(b, a, reason: 'seed=${0x5EED + trial}');
    });

    property('checkScheduleConflicts flags exactly a shared slot with the set',
        (trial, r) {
      // The incremental gatekeeper must report a class conflict iff the new
      // section shares a grid cell with any already-selected section — whether
      // or not that cell was already over-booked by others.
      final catalog = _randomCatalog(r);
      final selection = _randomSelection(r, catalog);

      final accepted = <SelectedSection>[];
      for (final s in selection) {
        final incrementalClash =
            ClashDetector.checkScheduleConflicts(s.section, accepted).isNotEmpty;
        final newSlots = _slotsOf(s.section);
        final oracle =
            accepted.any((a) => _slotsOf(a.section).any(newSlots.contains));

        expect(incrementalClash, oracle,
            reason: 'seed=${0x5EED + trial} adding ${s.courseCode}-${s.sectionId}\n'
                '${_describe([...accepted, s])}');
        accepted.add(s);
      }
    });

    test('empty selection has no clashes', () {
      expect(ClashDetector.detectClashes(const [], _randomCatalog(Random(1))),
          isEmpty);
    });
  });
}

// ── Random generators (no internal self-overlap: each section's schedule
// entries use distinct hours, so a section can never clash with itself) ──────

const _days = DayOfWeek.values;
const _midSlots = [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4];
const _compSlots = [TimeSlot.FN, TimeSlot.AN];

Section _randomSection(Random r, String id, SectionType type) {
  final entryCount = 1 + r.nextInt(2); // 1–2 schedule entries
  final hours = <int>{};
  while (hours.length < entryCount) {
    hours.add(1 + r.nextInt(9)); // hours 1..9, distinct across entries
  }
  final schedule = hours.map((h) {
    final dayCount = 1 + r.nextInt(3);
    final days = <DayOfWeek>{};
    while (days.length < dayCount) {
      days.add(_days[r.nextInt(_days.length)]);
    }
    return ScheduleEntry(days: days.toList(), hours: [h]);
  }).toList();
  return Section(
    sectionId: id,
    type: type,
    instructor: 'P',
    room: 'R',
    schedule: schedule,
  );
}

ExamSchedule? _randomExam(Random r, List<TimeSlot> slots) {
  if (r.nextInt(3) == 0) return null; // ~1/3 of courses have no such exam
  // Tight date window so collisions are frequent; midnight, as real data is.
  return ExamSchedule(
    date: DateTime(2026, 3, 1 + r.nextInt(4)),
    timeSlot: slots[r.nextInt(slots.length)],
  );
}

List<Course> _randomCatalog(Random r) {
  final n = 3 + r.nextInt(6); // 3–8 courses
  final courses = <Course>[];
  for (var i = 0; i < n; i++) {
    final types = <SectionType>{SectionType.L};
    if (r.nextBool()) types.add(SectionType.P);
    if (r.nextBool()) types.add(SectionType.T);
    final sections = <Section>[];
    var s = 0;
    for (final t in types) {
      final count = 1 + r.nextInt(2);
      for (var k = 0; k < count; k++) {
        sections.add(_randomSection(r, '${t.name}${s++}', t));
      }
    }
    courses.add(Course(
      courseCode: 'C$i',
      courseTitle: 'C$i',
      lectureCredits: 3,
      practicalCredits: 0,
      totalCredits: 3,
      sections: sections,
      midSemExam: _randomExam(r, _midSlots),
      endSemExam: _randomExam(r, _compSlots),
    ));
  }
  return courses;
}

List<SelectedSection> _randomSelection(Random r, List<Course> catalog) {
  final selection = <SelectedSection>[];
  for (final c in catalog) {
    if (r.nextInt(4) == 0) continue; // skip ~1/4 of courses entirely
    for (final section in c.sections) {
      if (r.nextBool()) {
        selection.add(SelectedSection(
          courseCode: c.courseCode,
          sectionId: section.sectionId,
          section: section,
        ));
      }
    }
  }
  return selection;
}

// ── Independent oracles ──────────────────────────────────────────────────────

Set<String> _slotsOf(Section s) {
  final slots = <String>{};
  for (final e in s.schedule) {
    for (final d in e.days) {
      for (final h in e.hours) {
        slots.add('${d.name}_$h');
      }
    }
  }
  return slots;
}

bool _anyPairSharesSlot(List<SelectedSection> sel) {
  for (var i = 0; i < sel.length; i++) {
    final a = _slotsOf(sel[i].section);
    for (var j = i + 1; j < sel.length; j++) {
      if (_slotsOf(sel[j].section).any(a.contains)) return true;
    }
  }
  return false;
}

/// Number of grid cells occupied by more than one selected section — the count
/// the detector emits one warning apiece for.
int _overbookedCells(List<SelectedSection> sel) {
  final counts = <String, int>{};
  for (final ss in sel) {
    for (final slot in _slotsOf(ss.section)) {
      counts[slot] = (counts[slot] ?? 0) + 1;
    }
  }
  return counts.values.where((c) => c > 1).length;
}

/// Number of (date, slot) groups holding ≥2 distinct courses for the given
/// exam type — one clash warning is expected per group.
int _examClashGroups(
  List<SelectedSection> sel,
  Map<String, Course> byCode, {
  required bool isMid,
}) {
  final groups = <String, Set<String>>{};
  for (final ss in sel) {
    final course = byCode[ss.courseCode];
    if (course == null) continue;
    final exam = isMid ? course.midSemExam : course.endSemExam;
    if (exam == null) continue;
    final key = '${exam.date.toIso8601String()}_${exam.timeSlot}';
    groups.putIfAbsent(key, () => <String>{}).add(course.courseCode);
  }
  return groups.values.where((codes) => codes.length > 1).length;
}

/// Stable, order-independent fingerprint of a warning list.
List<String> _signature(List<ClashWarning> warnings) {
  final sig = warnings
      .map((w) =>
          '${w.type}|${(w.conflictingCourses.toList()..sort()).join(",")}')
      .toList()
    ..sort();
  return sig;
}

String _describe(List<SelectedSection> sel) => sel
    .map((s) => '${s.courseCode}-${s.sectionId}:${_slotsOf(s.section).toList()..sort()}')
    .join('\n');
