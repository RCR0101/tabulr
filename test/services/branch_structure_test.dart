import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/branch_structure_service.dart';

/// The two readings of a branch's CDC list have to disagree on purpose: a
/// choice is *one* course to the student and *both* courses to anything asking
/// "is this core?" — an elective pool must not offer either alternative, and a
/// clash filter cannot know which one gets taken.
void main() {
  final structure = BranchStructure.fromMap({
    'branch_code': 'A7',
    'cdcs': {
      '3-1': ['CS F301', 'CS F211|CS F213', ''],
    },
    'dels': <String>[],
    'huels': <String>[],
  });

  test('cdcsForSemester flattens a choice into every alternative', () {
    expect(structure.cdcsForSemester('3-1'),
        ['CS F301', 'CS F211', 'CS F213']);
  });

  test('slotsForSemester keeps a choice as one requirement', () {
    final slots = structure.slotsForSemester('3-1');
    expect(slots.length, 2);
    expect(slots[0].isChoice, isFalse);
    expect(slots[1].isChoice, isTrue);
    expect(slots[1].options, ['CS F211', 'CS F213']);
  });

  test('an unknown semester is empty, not an error', () {
    expect(structure.cdcsForSemester('9-9'), isEmpty);
    expect(structure.slotsForSemester('9-9'), isEmpty);
  });
}
