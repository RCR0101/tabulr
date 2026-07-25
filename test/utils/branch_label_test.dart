import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/branch_constants.dart';

/// One branch label for the whole app.
///
/// The three elective browsers each showed half of it — Humanities the bare
/// code ("A7"), Discipline and Open the bare name ("Computer Science") — so the
/// same branch read differently depending on the screen.
void main() {
  test('pairs the code with its name', () {
    expect(branchLabel('A7'), 'A7 — Computer Science');
    expect(branchLabel('A1'), 'A1 — Chemical');
  });

  test('falls back to the code alone when the branch is unknown', () {
    // Better a bare code than an empty dropdown row.
    expect(branchLabel('ZZ'), 'ZZ');
  });

  test('every known branch produces a label containing both halves', () {
    for (final entry in branchCodeToName.entries) {
      final label = branchLabel(entry.key);
      expect(label, contains(entry.key));
      expect(label, contains(entry.value));
    }
  });
}
