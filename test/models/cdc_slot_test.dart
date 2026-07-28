import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/cdc_slot.dart';

void main() {
  group('CdcSlot', () {
    test('a plain code is a one-option slot', () {
      final slot = CdcSlot.tryParse('CS F211')!;
      expect(slot.options, ['CS F211']);
      expect(slot.isChoice, isFalse);
      expect(slot.encode(), 'CS F211');
    });

    test('parses a choice and survives a round trip', () {
      final slot = CdcSlot.tryParse(' CS F211 | CS F213 ')!;
      expect(slot.options, ['CS F211', 'CS F213']);
      expect(slot.isChoice, isTrue);
      expect(CdcSlot.tryParse(slot.encode()), slot);
    });

    test('a choice is not limited to two alternatives', () {
      final slot = CdcSlot.tryParse('CS F211|CS F213|CS F214')!;
      expect(slot.options.length, 3);
      expect(slot.isChoice, isTrue);
      expect(slot.resolve({'CS F214'}), 'CS F214');
      expect(
        CdcSlot.resolveAll(['CS F211|CS F213|CS F214'], {'CS F213'}),
        ['CS F213'],
      );
    });

    test('drops entries that name no course', () {
      expect(CdcSlot.tryParse(''), isNull);
      expect(CdcSlot.tryParse(' | '), isNull);
      expect(CdcSlot.parseAll(['CS F211', '', 'A|B']).length, 2);
    });

    test('expandAll flattens every alternative', () {
      expect(
        CdcSlot.expandAll(['CS F211', 'MATH F211|MATH F213']),
        ['CS F211', 'MATH F211', 'MATH F213'],
      );
    });

    test('resolveAll takes the picked alternative and keeps plain codes', () {
      expect(
        CdcSlot.resolveAll(
          ['CS F211', 'MATH F211|MATH F213', 'BIO F110|CHEM F110'],
          {'MATH F213', 'CHEM F110'},
        ),
        ['CS F211', 'MATH F213', 'CHEM F110'],
      );
    });

    test('an unanswered choice is left out, not guessed', () {
      expect(
        CdcSlot.resolveAll(['CS F211', 'MATH F211|MATH F213'], const {}),
        ['CS F211'],
      );
    });

    test('a pick for one choice cannot satisfy another', () {
      // Both slots are scanned against the same set, so an option listed in two
      // slots must not silently answer the slot the student never saw.
      expect(
        CdcSlot.resolveAll(['A|B', 'C|D'], {'B'}),
        ['B'],
      );
    });

    test('choices sharing an alternative each keep their own pick', () {
      // A is picked for the first slot; without consuming it, it would also
      // answer the second and the student would lose the C they chose.
      expect(
        CdcSlot.resolveAll(['A|B', 'A|C'], {'A', 'C'}),
        ['A', 'C'],
      );
    });
  });
}
