import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/elective_pool.dart';

/// A CS student: CS F211 is core, CS F301 a discipline elective, HSS F226 a
/// humanities one, and BIO F110 belongs to none of their requirements.
const _pools = ElectivePools(
  cdcs: {'CS F211', 'MATH F211'},
  dels: {'CS F301', 'CS F342'},
  huels: {'HSS F226'},
);

void main() {
  group('ElectivePools', () {
    test('each requirement list is its own pool', () {
      expect(_pools.contains(ElectivePool.discipline, 'CS F301'), isTrue);
      expect(_pools.contains(ElectivePool.humanities, 'HSS F226'), isTrue);
      expect(_pools.contains(ElectivePool.discipline, 'HSS F226'), isFalse);
      expect(_pools.contains(ElectivePool.humanities, 'CS F301'), isFalse);
    });

    test('open is everything outside the three requirement sets', () {
      // Another discipline's course is a legitimate OPEL, which is the whole
      // reason the pools are branch-relative.
      expect(_pools.contains(ElectivePool.open, 'BIO F110'), isTrue);
      // Your own core never is, whichever semester it falls in.
      expect(_pools.contains(ElectivePool.open, 'CS F211'), isFalse);
      expect(_pools.contains(ElectivePool.open, 'MATH F211'), isFalse);
      // Nor is a course already counted in one of your elective requirements.
      expect(_pools.contains(ElectivePool.open, 'CS F301'), isFalse);
      expect(_pools.contains(ElectivePool.open, 'HSS F226'), isFalse);
    });

    test('several selected pools mean their union', () {
      const both = {ElectivePool.discipline, ElectivePool.humanities};
      expect(_pools.matchesAny(both, 'CS F301'), isTrue);
      expect(_pools.matchesAny(both, 'HSS F226'), isTrue);
      expect(_pools.matchesAny(both, 'BIO F110'), isFalse,
          reason: 'an OPEL is not a DEL or a HUEL');
    });

    test('no pools selected passes everything', () {
      // The filter is off, not "match nothing" — an empty chip row must not
      // empty the course list.
      expect(_pools.matchesAny(const {}, 'CS F211'), isTrue);
      expect(_pools.matchesAny(const {}, 'BIO F110'), isTrue);
    });

    test('an unresolved branch classifies nothing', () {
      // Guards the filter's skip condition: with no branch every course would
      // otherwise read as an OPEL, and selecting DEL would empty the list.
      expect(ElectivePools.empty.isEmpty, isTrue);
      expect(_pools.isEmpty, isFalse);
    });
  });
}
