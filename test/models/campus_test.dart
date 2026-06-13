import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';

void main() {
  group('Campus', () {
    test('code returns enum name', () {
      expect(Campus.hyderabad.code, 'hyderabad');
      expect(Campus.pilani.code, 'pilani');
      expect(Campus.goa.code, 'goa');
    });

    test('fromCode resolves valid codes', () {
      expect(Campus.fromCode('hyderabad'), Campus.hyderabad);
      expect(Campus.fromCode('pilani'), Campus.pilani);
      expect(Campus.fromCode('goa'), Campus.goa);
    });

    test('fromCode defaults to hyderabad for unknown code', () {
      expect(Campus.fromCode('mumbai'), Campus.hyderabad);
      expect(Campus.fromCode(''), Campus.hyderabad);
    });

    test('roundtrip code -> fromCode', () {
      for (final campus in Campus.values) {
        expect(Campus.fromCode(campus.code), campus);
      }
    });
  });
}
