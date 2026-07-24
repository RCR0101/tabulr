import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/models/course_type.dart';
import '../helpers/test_reporter.dart';

/// Property / metamorphic stress tests for the CGPA maths.
///
/// cgpa_data_test.dart pins the BITS regulation clauses to specific worked
/// examples; this fuzzes hundreds of random transcripts and asserts the same
/// rules hold as *invariants*, checked against an independent oracle that
/// re-implements the credit-weighted, latest-letter-grade-wins average. It also
/// hammers the numerical edges (zero credits, all-report semesters, junk grade
/// strings) that hand-written examples rarely reach.
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
    await TestReporter.reportTestResults('cgpa_data_property', results);
  });

  void property(String name, void Function(int trial, Random r) body,
      {int trials = 500}) {
    test(name, () {
      final sw = Stopwatch()..start();
      try {
        for (var i = 0; i < trials; i++) {
          body(i, Random(0xC69A + i));
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

  group('CGPA invariants', () {
    property('cgpa equals the independent credit-weighted oracle', (trial, r) {
      final data = _randomData(r);
      expect(data.cgpa, closeTo(_oracleCgpa(data.semesters), 1e-9),
          reason: 'seed=${0xC69A + trial}\n${_describe(data)}');
    });

    property('cgpa is always finite and in {0} ∪ [2, 10]', (trial, r) {
      final data = _randomData(r);
      final v = data.cgpa;
      expect(v.isFinite, isTrue, reason: 'seed=${0xC69A + trial} cgpa=$v');
      // Letter grades span E(2)..A(10); 0 only when nothing counts.
      final ok = v == 0.0 || (v >= 2.0 - 1e-9 && v <= 10.0 + 1e-9);
      expect(ok, isTrue,
          reason: 'seed=${0xC69A + trial} cgpa=$v\n${_describe(data)}');
    });

    property('reports and ATC courses never change the CGPA (clause 4.21)',
        (trial, r) {
      final data = _randomData(r);
      final before = data.cgpa;

      // Sprinkle report-graded and ATC courses across every semester — some
      // reusing existing codes, some fresh. None may move the CGPA.
      final polluted = <String, SemesterData>{};
      data.semesters.forEach((name, sem) {
        final extra = <CourseEntry>[...sem.courses];
        final count = r.nextInt(3);
        for (var i = 0; i < count; i++) {
          final reuse = sem.courses.isNotEmpty && r.nextBool();
          extra.add(CourseEntry(
            courseCode: reuse
                ? sem.courses[r.nextInt(sem.courses.length)].courseCode
                : 'NOISE${trial}_${name}_$i',
            courseTitle: 'noise',
            credits: (1 + r.nextInt(4)).toDouble(),
            courseType: r.nextBool() ? CourseType.atc : CourseType.normal,
            grade: r.nextBool()
                ? _reports[r.nextInt(_reports.length)]
                : (r.nextBool() ? null : _junk[r.nextInt(_junk.length)]),
          ));
        }
        polluted[name] = SemesterData(semesterName: name, courses: extra);
      });

      expect(CGPAData(semesters: polluted).cgpa, closeTo(before, 1e-9),
          reason: 'seed=${0xC69A + trial}\n${_describe(data)}');
    });

    property('a later report never displaces an earlier letter grade', (trial, r) {
      // Letter grade in an early semester, a report for the same course later:
      // the letter grade must still count.
      final grade = _letters[r.nextInt(_letters.length)];
      final credits = (2 + r.nextInt(4)).toDouble();
      final report = _reports[r.nextInt(_reports.length)];
      final data = CGPAData(semesters: {
        '1-1': SemesterData(semesterName: '1-1', courses: [
          CourseEntry(
              courseCode: 'X',
              courseTitle: 'x',
              credits: credits,
              courseType: CourseType.normal,
              grade: grade),
        ]),
        '2-1': SemesterData(semesterName: '2-1', courses: [
          CourseEntry(
              courseCode: 'X',
              courseTitle: 'x',
              credits: credits,
              courseType: CourseType.normal,
              grade: report),
        ]),
      });
      expect(data.cgpa, closeTo(_points[grade]!, 1e-9),
          reason: 'seed=${0xC69A + trial} grade=$grade report=$report');
    });

    property('a later letter grade replaces an earlier one (repeat)', (trial, r) {
      final first = _letters[r.nextInt(_letters.length)];
      final second = _letters[r.nextInt(_letters.length)];
      final credits = (2 + r.nextInt(4)).toDouble();
      final data = CGPAData(semesters: {
        '1-1': SemesterData(semesterName: '1-1', courses: [
          CourseEntry(
              courseCode: 'X',
              courseTitle: 'x',
              credits: credits,
              courseType: CourseType.normal,
              grade: first),
        ]),
        '3-1': SemesterData(semesterName: '3-1', courses: [
          CourseEntry(
              courseCode: 'X',
              courseTitle: 'x',
              credits: credits,
              courseType: CourseType.normal,
              grade: second),
        ]),
      });
      // Only the later attempt counts.
      expect(data.cgpa, closeTo(_points[second]!, 1e-9),
          reason: 'seed=${0xC69A + trial} first=$first second=$second');
    });

    property('cgpa is independent of map and course insertion order', (trial, r) {
      final data = _randomData(r);

      final shuffledNames = data.semesters.keys.toList()..shuffle(r);
      final reordered = <String, SemesterData>{};
      for (final name in shuffledNames) {
        final sem = data.semesters[name]!;
        reordered[name] = SemesterData(
          semesterName: name,
          courses: [...sem.courses]..shuffle(r),
        );
      }

      expect(CGPAData(semesters: reordered).cgpa, closeTo(data.cgpa, 1e-9),
          reason: 'seed=${0xC69A + trial}\n${_describe(data)}');
    });

    property('sgpa never produces NaN/Infinity on degenerate semesters',
        (trial, r) {
      // Zero-credit courses, all-report semesters, all-ATC semesters, empties.
      final courses = <CourseEntry>[];
      final kind = r.nextInt(4);
      final n = r.nextInt(4);
      for (var i = 0; i < n; i++) {
        courses.add(CourseEntry(
          courseCode: 'D$i',
          courseTitle: 'd',
          credits: kind == 0 ? 0.0 : (r.nextInt(5)).toDouble(),
          courseType: kind == 2 ? CourseType.atc : CourseType.normal,
          grade: kind == 1
              ? _reports[r.nextInt(_reports.length)]
              : _letters[r.nextInt(_letters.length)],
        ));
      }
      final sem = SemesterData(semesterName: '1-1', courses: courses);
      expect(sem.sgpa.isFinite, isTrue,
          reason: 'seed=${0xC69A + trial} sgpa=${sem.sgpa}');
      expect(sem.totalCredits.isFinite && sem.totalGradePoints.isFinite, isTrue);
      final cg = CGPAData(semesters: {'1-1': sem}).cgpa;
      expect(cg.isFinite, isTrue, reason: 'seed=${0xC69A + trial} cgpa=$cg');
    });

    property('requiredSgpa inverts the CGPA formula', (trial, r) {
      final data = _randomData(r);
      final target = 2 + r.nextDouble() * 8; // 2..10
      final next = 1 + r.nextDouble() * 20; // >0
      final req = data.requiredSgpa(targetCgpa: target, nextCredits: next);

      // Feeding a future semester of `next` credits at exactly `req` SGPA must
      // land the CGPA on `target`.
      final cur = data.effectiveTotalCredits;
      final curPts = data.effectiveTotalGradePoints;
      final reproduced = (curPts + req * next) / (cur + next);
      expect(reproduced, closeTo(target, 1e-6),
          reason: 'seed=${0xC69A + trial} target=$target next=$next req=$req');
    });
  });
}

// ── Independent oracle data (hardcoded, not imported from product code) ──────

const Map<String, double> _points = {
  'A': 10.0, 'A-': 9.0, 'B': 8.0, 'B-': 7.0,
  'C': 6.0, 'C-': 5.0, 'D': 4.0, 'D-': 3.0, 'E': 2.0,
};
const List<String> _letters = ['A', 'A-', 'B', 'B-', 'C', 'C-', 'D', 'D-', 'E'];
const List<String> _reports = ['NC', 'W', 'RC', 'I', 'GA'];
const List<String> _junk = ['X', 'ZZ', '', 'pass', '11'];

/// Independent CGPA: latest letter-graded normal attempt per course, ordered by
/// the canonical semester list, credit-weighted.
double _oracleCgpa(Map<String, SemesterData> semesters) {
  final order = [
    ...SemesterConstants.all.where(semesters.containsKey),
    ...semesters.keys.where((k) => !SemesterConstants.all.contains(k)),
  ];
  final latest = <String, CourseEntry>{};
  for (final name in order) {
    for (final c in semesters[name]!.courses) {
      if (c.courseType == CourseType.normal && _points.containsKey(c.grade)) {
        latest[c.courseCode] = c;
      }
    }
  }
  var gp = 0.0, cr = 0.0;
  for (final c in latest.values) {
    gp += c.credits * _points[c.grade]!;
    cr += c.credits;
  }
  return cr > 0 ? gp / cr : 0.0;
}

// ── Random transcript generator ──────────────────────────────────────────────

/// Small code pool so repeats (and thus the dedup path) happen often.
const _codePool = ['CS', 'MA', 'PH', 'EE', 'BIO', 'HSS', 'ME', 'CHEM'];

CGPAData _randomData(Random r) {
  final semCount = 1 + r.nextInt(5);
  final names = ([...SemesterConstants.all]..shuffle(r)).take(semCount).toList();
  final semesters = <String, SemesterData>{};
  for (final name in names) {
    final courses = <CourseEntry>[];
    // Unique codes *within* a semester (a course is not taken twice in one
    // term); repeats across semesters still exercise the dedup path.
    final codes = ([..._codePool]..shuffle(r));
    final n = r.nextInt(6);
    for (var i = 0; i < n; i++) {
      courses.add(CourseEntry(
        courseCode: codes[i],
        courseTitle: 't',
        credits: [0.0, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0][r.nextInt(7)],
        courseType: r.nextInt(5) == 0 ? CourseType.atc : CourseType.normal,
        grade: _randomGrade(r),
      ));
    }
    semesters[name] = SemesterData(semesterName: name, courses: courses);
  }
  return CGPAData(semesters: semesters);
}

String? _randomGrade(Random r) {
  switch (r.nextInt(10)) {
    case 0:
      return null;
    case 1:
      return _reports[r.nextInt(_reports.length)];
    case 2:
      return _junk[r.nextInt(_junk.length)];
    default:
      return _letters[r.nextInt(_letters.length)];
  }
}

String _describe(CGPAData data) => data.semesters.entries
    .map((e) =>
        '${e.key}: ${e.value.courses.map((c) => '${c.courseCode}/${c.courseType == CourseType.atc ? 'ATC' : ''}${c.grade}@${c.credits}').join(', ')}')
    .join('\n');
