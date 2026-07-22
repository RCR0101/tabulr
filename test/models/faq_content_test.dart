import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/faq_content.dart';

void main() {
  final allEntries = [for (final c in faqCategories) ...c.entries];

  group('content', () {
    test('every category has a title and at least one entry', () {
      expect(faqCategories, isNotEmpty);
      for (final c in faqCategories) {
        expect(c.title.trim(), isNotEmpty);
        expect(c.entries, isNotEmpty, reason: '${c.title} is empty');
      }
    });

    test('category titles are unique — they key the filter chips', () {
      final titles = faqCategories.map((c) => c.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('questions are unique within a category', () {
      for (final c in faqCategories) {
        final questions = c.entries.map((e) => e.question).toList();
        expect(questions.toSet().length, questions.length,
            reason: '${c.title} repeats a question');
      }
    });

    test('every entry has a question and a non-trivial answer', () {
      for (final e in allEntries) {
        expect(e.question.trim(), isNotEmpty);
        expect(e.answer.trim().length, greaterThan(20),
            reason: '"${e.question}" has a stub answer');
      }
    });

    test('answers stay short enough to scan', () {
      // The lead paragraph is meant to be the short version; detail belongs in
      // bullets or the cited clause.
      for (final e in allEntries) {
        expect(e.answer.length, lessThan(320),
            reason: '"${e.question}" is too long for a lead paragraph');
      }
    });

    test('every entry cites a source so claims are verifiable', () {
      for (final e in allEntries) {
        expect(e.source, isNotNull, reason: '"${e.question}" has no source');
        expect(e.source!.trim(), isNotEmpty);
      }
    });

    test('no bullet is empty', () {
      for (final e in allEntries) {
        for (final b in e.bullets) {
          expect(b.trim(), isNotEmpty, reason: '"${e.question}" has a blank bullet');
        }
      }
    });
  });

  group('search', () {
    test('an empty query matches everything', () {
      for (final e in allEntries) {
        expect(e.matches(''), isTrue);
      }
    });

    test('matching is case-insensitive', () {
      final e = allEntries.firstWhere((e) => e.question.contains('CGPA'));
      expect(e.matches('cgpa'), isTrue);
      expect(e.matches('CGPA'), isTrue);
    });

    test('keywords surface entries whose visible text lacks the term', () {
      // "compre" is how students refer to the comprehensive exam; it only
      // exists in the evaluation entry's keywords.
      final hits = allEntries.where((e) => e.matches('compre')).toList();
      expect(hits, isNotEmpty);
    });

    test('common student phrasings all find something', () {
      for (final term in [
        'cgpa',
        'nc',
        'repeat',
        'practice school',
        'minor',
        'summer',
        'graduate',
        'audit',
        'makeup',
        'electives',
        'withdraw',
        'drop',
        'transfer',
        'dual degree',
        'deadline',
        'branch change',
        'improve',
      ]) {
        expect(allEntries.any((e) => e.matches(term)), isTrue,
            reason: 'no FAQ answers "$term"');
      }
    });

    test('a nonsense query matches nothing', () {
      expect(allEntries.any((e) => e.matches('zzzqqqxxx')), isFalse);
    });

    test('bullets are searchable, not just the answer', () {
      // "Distinction" appears only in the division entry's bullets.
      final hits = allEntries.where((e) => e.matches('Distinction')).toList();
      expect(hits, isNotEmpty);
    });
  });
}
