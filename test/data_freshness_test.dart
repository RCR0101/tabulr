import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/data_freshness.dart';

void main() {
  group('currentTermStart', () {
    test('odd semester starts counting from July', () {
      expect(currentTermStart(DateTime(2026, 10, 3)), DateTime(2026, 7));
      expect(currentTermStart(DateTime(2026, 7, 1)), DateTime(2026, 7));
    });
    test('even semester starts counting from the December before', () {
      expect(currentTermStart(DateTime(2026, 12, 15)), DateTime(2026, 12));
      expect(currentTermStart(DateTime(2027, 3, 1)), DateTime(2026, 12));
      expect(currentTermStart(DateTime(2027, 6, 30)), DateTime(2026, 12));
    });
  });

  group('freshnessOf', () {
    final now = DateTime(2026, 10, 3);
    test('uploaded this term is current', () {
      expect(freshnessOf(DateTime(2026, 8, 1), now), Freshness.current);
    });
    test('last term is stale', () {
      expect(freshnessOf(DateTime(2026, 5, 1), now), Freshness.stale);
    });
    test('never uploaded is missing', () {
      expect(freshnessOf(null, now), Freshness.missing);
    });
  });

  test('defaultExamYear rolls over for December uploads', () {
    expect(defaultExamYear(DateTime(2026, 7, 20)), 2026);
    expect(defaultExamYear(DateTime(2026, 12, 10)), 2027);
    expect(defaultExamYear(DateTime(2027, 1, 5)), 2027);
  });

  test('parseUploadStamp reads ISO strings and rejects junk', () {
    expect(parseUploadStamp('2026-08-01T10:00:00Z'), DateTime.utc(2026, 8, 1, 10));
    expect(parseUploadStamp('nope'), isNull);
    expect(parseUploadStamp(42), isNull);
    expect(parseUploadStamp(null), isNull);
  });
}
