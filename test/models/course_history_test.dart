import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course_history.dart';

/// One term entry in the shape `record_term_offerings` writes.
///
/// No title and no credits: courses_master is the only source of both, and the
/// client resolves them at load. See the note on [CourseTimeline.offerings].
///
/// `ic` is the capitalised subset — whoever ran the course that term.
Map<String, dynamic> term(
  String id,
  Map<String, ({List<String> profs, int sections, List<String> ic})> courses,
) {
  return {
    'term': id,
    'courses': {
      for (final entry in courses.entries)
        entry.key: {
          'instructors': entry.value.profs,
          'ic': entry.value.ic,
          'sections': entry.value.sections,
        },
    },
  };
}

void main() {
  group('Terms', () {
    test('labels a term id the way a student reads it', () {
      expect(Terms.label('2026-27-1'), 'Sem 1 · 2026-27');
      expect(Terms.tickLabel('2026-27-2'), "S2 '26");
    });

    test('an unrecognised id falls back to itself rather than throwing', () {
      expect(Terms.label('nonsense'), 'nonsense');
      expect(Terms.tickLabel(''), '');
    });

    test('says how long ago in words', () {
      expect(Terms.relative(0), 'This semester');
      expect(Terms.relative(1), 'Last semester');
      expect(Terms.relative(4), '4 semesters ago');
    });

    test('distance counts real semesters across the archive hole', () {
      // Hyderabad has no booklet for 2022-23 or 2023-24, so 2021-22-2 and
      // 2024-25-1 are adjacent ON RECORD but five semesters apart in fact.
      expect(Terms.distance('2021-22-2', '2024-25-1'), 5);
      expect(Terms.distance('2021-22-2', '2026-27-1'), 9);
      expect(Terms.distance('2026-27-1', '2026-27-1'), 0);
      expect(Terms.distance('2025-26-2', '2026-27-1'), 1);
    });

    test('distance is null for an unparseable id, never a wrong number', () {
      expect(Terms.distance('nonsense', '2026-27-1'), isNull);
      expect(Terms.ordinal('2026-27'), isNull);
    });

    test('consecutive means nothing is missing in between', () {
      expect(Terms.areConsecutive('2025-26-2', '2026-27-1'), isTrue);
      expect(Terms.areConsecutive('2026-27-1', '2026-27-2'), isTrue);
      expect(Terms.areConsecutive('2021-22-2', '2024-25-1'), isFalse);
    });
  });

  group('gaps in the record', () {
    // Six terms on record with a five-semester hole in the middle, mirroring
    // the real Hyderabad archive.
    final holed = [
      term('2021-22-1', {
        'CS_F211': (profs: ['C HOTA'], sections: 4, ic: ['C HOTA']),
        'BIO_F421': (profs: ['A SANYAL'], sections: 1, ic: ['A SANYAL']),
      }),
      term('2021-22-2', {
        'CS_F211': (profs: ['C HOTA'], sections: 4, ic: ['C HOTA']),
        'BIO_F421': (profs: ['A SANYAL'], sections: 1, ic: ['A SANYAL']),
      }),
      term('2024-25-1', {
        'CS_F211': (profs: ['C HOTA'], sections: 5, ic: ['C HOTA']),
      }),
      term('2026-27-1', {
        'CS_F211': (profs: ['C HOTA'], sections: 6, ic: ['C HOTA']),
      }),
    ];

    test('a course that stopped before the hole reports real semesters', () {
      final history = CourseHistory.fromBundle(holed);
      final stopped =
          history.courses.firstWhere((c) => c.courseCode == 'BIO F421');
      // Position in the recorded list would say 2. It has really been 9.
      expect(stopped.termsSinceOffered(history.terms), 9);
      expect(Terms.relative(stopped.termsSinceOffered(history.terms)),
          '9 semesters ago');
    });

    test('a course still running is unaffected by the hole', () {
      final history = CourseHistory.fromBundle(holed);
      final live = history.courses.firstWhere((c) => c.courseCode == 'CS F211');
      expect(live.termsSinceOffered(history.terms), 0);
    });

    test('an instructor who stopped before the hole reports real semesters', () {
      final history = CourseHistory.fromBundle(holed);
      final gone =
          history.instructors.firstWhere((p) => p.name == 'A SANYAL');
      expect(gone.termsSinceActive(history.terms), 9);
    });
  });

  group('CourseHistory.fromBundle', () {
    final bundle = [
      term('2025-26-1', {
        'CS_F211': (profs: ['R ADURI'], sections: 4, ic: ['R ADURI']),
        'CS_F407': (profs: ['N GOVEAS'], sections: 1, ic: ['N GOVEAS']),
      }),
      term('2025-26-2', {
        'CS_F211': (profs: ['C HOTA'], sections: 5, ic: ['C HOTA']),
      }),
      term('2026-27-1', {
        // Hota runs it, Aduri teaches a section of it.
        'CS_F211':
            (profs: ['C HOTA', 'R ADURI'], sections: 6, ic: ['C HOTA']),
        'CS_F491': (profs: ['N GOVEAS'], sections: 1, ic: []),
      }),
    ];

    test('indexes courses by code, with document ids turned back into codes', () {
      final history = CourseHistory.fromBundle(bundle);
      expect(history.courses.map((c) => c.courseCode),
          ['CS F211', 'CS F407', 'CS F491']);
    });

    test('orders terms chronologically however the bundle arrived', () {
      // Deliberately reversed: "last offered" is read off the END of each
      // course's offering list, so a bundle in any other order would lie.
      final history = CourseHistory.fromBundle(bundle.reversed.toList());
      expect(history.terms, ['2025-26-1', '2025-26-2', '2026-27-1']);
      expect(history.currentTerm, '2026-27-1');
      final dsa = history.courses.first;
      expect(dsa.offerings.map((o) => o.term),
          ['2025-26-1', '2025-26-2', '2026-27-1']);
      expect(dsa.lastOfferedTerm, '2026-27-1');
    });

    test('a course keeps only the terms it actually ran in', () {
      final history = CourseHistory.fromBundle(bundle);
      final ai = history.courses.firstWhere((c) => c.courseCode == 'CS F407');
      expect(ai.offerings.map((o) => o.term), ['2025-26-1']);
      expect(ai.offeringIn('2025-26-2'), isNull);
      expect(ai.timesOffered, 1);
    });

    test('the gap since a course last ran counts terms, not entries', () {
      final history = CourseHistory.fromBundle(bundle);
      final ai = history.courses.firstWhere((c) => c.courseCode == 'CS F407');
      final dsa = history.courses.firstWhere((c) => c.courseCode == 'CS F211');
      expect(ai.termsSinceOffered(history.terms), 2);
      expect(dsa.termsSinceOffered(history.terms), 0);
    });

    test('a course first seen in the newest term is new; older ones are not', () {
      final history = CourseHistory.fromBundle(bundle);
      final project = history.courses.firstWhere((c) => c.courseCode == 'CS F491');
      final dsa = history.courses.firstWhere((c) => c.courseCode == 'CS F211');
      expect(project.isNewIn(history.terms), isTrue);
      expect(dsa.isNewIn(history.terms), isFalse);
    });

    test('instructors are deduplicated and led by the most recent term', () {
      final history = CourseHistory.fromBundle(bundle);
      final dsa = history.courses.first;
      // R ADURI taught the oldest AND the newest term; C HOTA the middle one.
      // Newest first, so both of this semester's names lead, and neither repeats.
      expect(dsa.instructors, ['C HOTA', 'R ADURI']);
    });

    test('builds the professor side of the same data', () {
      final history = CourseHistory.fromBundle(bundle);
      expect(history.instructors.map((p) => p.name),
          ['C HOTA', 'N GOVEAS', 'R ADURI']);

      final goveas =
          history.instructors.firstWhere((p) => p.name == 'N GOVEAS');
      expect(goveas.displayName, 'N Goveas');
      expect(goveas.coursesByTerm['2025-26-1'], ['CS F407']);
      expect(goveas.coursesByTerm.containsKey('2025-26-2'), isFalse);
      // Most recent term's courses lead, and nothing repeats.
      expect(goveas.courses, ['CS F491', 'CS F407']);
      expect(goveas.lastActiveTerm, '2026-27-1');
      expect(goveas.termsSinceActive(history.terms), 0);

      final hota = history.instructors.firstWhere((p) => p.name == 'C HOTA');
      expect(hota.terms, ['2025-26-2', '2026-27-1']);
    });

    test('a term with no courses is not a term on record', () {
      // record_term_offerings will not write one, but a hand-edited bundle
      // would otherwise add a phantom column to every strip.
      final history = CourseHistory.fromBundle([
        term('2025-26-1', {
          'CS_F211': (profs: ['R ADURI'], sections: 1, ic: ['R ADURI'])
        }),
        term('2025-26-2', {}),
      ]);
      expect(history.terms, ['2025-26-1']);
    });

    test('an empty bundle is an empty history, not a crash', () {
      final history = CourseHistory.fromBundle([]);
      expect(history.isEmpty, isTrue);
      expect(history.currentTerm, isNull);
      expect(CourseHistory.empty.isEmpty, isTrue);
    });

    test('a missing field falls back rather than throwing', () {
      final history = CourseHistory.fromBundle([
        {'term': '2026-27-1', 'courses': {'CS_F211': <String, dynamic>{}}}
      ]);
      final offering = history.courses.single.offerings.single;
      expect(offering.instructors, isEmpty);
      expect(offering.inCharge, isEmpty);
      expect(offering.sections, 0);
    });

    test('separates who ran a course from who taught a section of it', () {
      final history = CourseHistory.fromBundle(bundle);
      final now = history.courses.first.offeringIn('2026-27-1')!;
      expect(now.inCharge, ['C HOTA']);
      expect(now.supporting, ['R ADURI']);
      // The in-charge stays in the full list too — it is a subset, not a split.
      expect(now.instructors, ['C HOTA', 'R ADURI']);
    });

    test('a term with no capitalised name leaves nobody in charge', () {
      final history = CourseHistory.fromBundle(bundle);
      final project =
          history.courses.firstWhere((c) => c.courseCode == 'CS F491');
      final offering = project.offeringIn('2026-27-1')!;
      expect(offering.inCharge, isEmpty);
      expect(offering.supporting, ['N GOVEAS']);
    });

    test('the professor side records which courses they ran', () {
      final history = CourseHistory.fromBundle(bundle);
      final hota = history.instructors.firstWhere((p) => p.name == 'C HOTA');
      final aduri = history.instructors.firstWhere((p) => p.name == 'R ADURI');

      expect(hota.wasInChargeOf('2026-27-1', 'CS F211'), isTrue);
      // Aduri teaches CS F211 this term but does not run it.
      expect(aduri.coursesByTerm['2026-27-1'], ['CS F211']);
      expect(aduri.wasInChargeOf('2026-27-1', 'CS F211'), isFalse);
      // He did run it two terms earlier, so "ever" is not "now".
      expect(aduri.wasInChargeOf('2025-26-1', 'CS F211'), isTrue);
      expect(aduri.everInCharge, {'CS F211'});

      // CS F491 had nobody capitalised, so Goveas only ever ran CS F407.
      final goveas =
          history.instructors.firstWhere((p) => p.name == 'N GOVEAS');
      expect(goveas.everInCharge, {'CS F407'});
    });
  });
}
