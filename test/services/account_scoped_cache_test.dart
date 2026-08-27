import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/core/account_scoped_cache.dart';

void main() {
  group('AccountScopedCache', () {
    test('only returns a value to the owner that populated it', () {
      final cache = AccountScopedCache<String>();
      cache.write('user-a', 'private-a');

      expect(cache.read('user-a'), 'private-a');
      expect(cache.read('user-b'), isNull);
      expect(cache.contains('user-b'), isFalse);
    });

    test('switching owners replaces the inaccessible old value', () {
      final cache = AccountScopedCache<String>();
      cache.write('user-a', 'private-a');
      cache.write('user-b', 'private-b');

      expect(cache.read('user-a'), isNull);
      expect(cache.read('user-b'), 'private-b');
    });

    test('clear removes both value and ownership', () {
      final cache = AccountScopedCache<String>();
      cache.write('user-a', 'private-a');
      cache.clear();

      expect(cache.read('user-a'), isNull);
      expect(cache.contains('user-a'), isFalse);
    });
  });
}
