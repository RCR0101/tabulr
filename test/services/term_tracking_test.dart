import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/data/config_service.dart';

void main() {
  group('ConfigService.isTermPast', () {
    test('is false when term tracking has never been configured', () {
      // Guards the rollout: before an admin runs a rollover, no timetable may
      // be treated as stale.
      expect(
        ConfigService.isTermPast(currentTerm: '', term: '2025-2026_sem1'),
        isFalse,
      );
    });

    test('is false for a timetable predating the term stamp', () {
      expect(
        ConfigService.isTermPast(currentTerm: '2026-2027_sem1', term: null),
        isFalse,
      );
      expect(
        ConfigService.isTermPast(currentTerm: '2026-2027_sem1', term: ''),
        isFalse,
      );
    });

    test('is false within the current term', () {
      expect(
        ConfigService.isTermPast(
          currentTerm: '2026-2027_sem1',
          term: '2026-2027_sem1',
        ),
        isFalse,
      );
    });

    test('is true for a timetable from an earlier term', () {
      expect(
        ConfigService.isTermPast(
          currentTerm: '2026-2027_sem1',
          term: '2025-2026_sem2',
        ),
        isTrue,
      );
    });
  });

  group('Timetable term stamp', () {
    Timetable make({String? term}) => Timetable(
          id: '1',
          name: 'Sem 1',
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 2),
          campus: Campus.hyderabad,
          availableCourses: const [],
          selectedSections: const [],
          clashWarnings: const [],
          term: term,
        );

    test('survives a local storage round trip', () {
      final restored = Timetable.fromJson(make(term: '2026-2027_sem1').toJson());
      expect(restored.term, '2026-2027_sem1');
    });

    test('survives a Firestore round trip', () {
      final restored =
          Timetable.fromJson(make(term: '2026-2027_sem1').toFirestoreJson());
      expect(restored.term, '2026-2027_sem1');
    });

    test('is omitted rather than written as null when unstamped', () {
      expect(make().toJson().containsKey('term'), isFalse);
      expect(make().toFirestoreJson().containsKey('term'), isFalse);
      expect(Timetable.fromJson(make().toJson()).term, isNull);
    });

    test('is carried through copyWith', () {
      final copied = make(term: '2026-2027_sem1').copyWith(name: 'Renamed');
      expect(copied.term, '2026-2027_sem1');
      expect(copied.name, 'Renamed');
    });

    test('can be adopted by an unstamped timetable', () {
      final tt = make();
      expect(tt.term, isNull);
      tt.term = '2026-2027_sem1';
      expect(Timetable.fromJson(tt.toJson()).term, '2026-2027_sem1');
    });
  });
}
