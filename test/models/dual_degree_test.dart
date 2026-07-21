import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/branch_constants.dart';

void main() {
  group('dualDegreePair', () {
    test('resolves MSc primary + BE secondary', () {
      final pair = dualDegreePair('B5', 'A7');
      expect(pair?.msc, 'B5');
      expect(pair?.be, 'A7');
    });

    test('resolves the same degree entered in the opposite order', () {
      // A student may nominate either half as primary. Both orderings describe
      // one degree, and the merge is asymmetric, so roles must be resolved
      // rather than assumed from position.
      final pair = dualDegreePair('A7', 'B5');
      expect(pair?.msc, 'B5');
      expect(pair?.be, 'A7');
    });

    test('is null for a single degree', () {
      expect(dualDegreePair('A7', null), isNull);
      expect(dualDegreePair('B5', null), isNull);
    });

    test('is null when the same branch is given twice', () {
      expect(dualDegreePair('A7', 'A7'), isNull);
    });

    test('is null for two branches of the same kind', () {
      expect(dualDegreePair('A7', 'A4'), isNull);
      expect(dualDegreePair('B5', 'B4'), isNull);
    });

    test('every known branch code classifies as exactly one kind', () {
      for (final code in branchCodeToName.keys) {
        expect(
          isMscBranch(code) != isBeBranch(code),
          isTrue,
          reason: '$code must be either MSc or BE, not both or neither',
        );
      }
    });

    test('resolves a pair for every MSc and BE combination', () {
      final msc = branchCodeToName.keys.where(isMscBranch);
      final be = branchCodeToName.keys.where(isBeBranch);
      expect(msc, isNotEmpty);
      expect(be, isNotEmpty);

      for (final m in msc) {
        for (final b in be) {
          expect(dualDegreePair(m, b), isNotNull, reason: '$m + $b');
          expect(dualDegreePair(b, m), isNotNull, reason: '$b + $m');
        }
      }
    });
  });
}
