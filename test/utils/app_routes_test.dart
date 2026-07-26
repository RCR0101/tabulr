import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/app_routes.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';

void main() {
  group('AppRoutes.screenIn', () {
    test('resolves a public destination by its slug', () {
      expect(AppRoutes.screenIn(Uri.parse('https://tabulr.net/exam-seating')),
          DrawerScreen.examSeating);
      expect(AppRoutes.screenIn(Uri.parse('/minors')), DrawerScreen.minors);
    });

    test('ignores a destination the current user cannot reach', () {
      // No Firebase in a unit test, so `isVisible` fails closed and every
      // signed-in-only destination is unreachable. That is the same path a
      // guest following a stale /cgpa link takes: land on the default screen,
      // not on an empty one.
      expect(AppRoutes.screenIn(Uri.parse('/cgpa')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/admin')), isNull);
    });

    test('ignores the root, unknown slugs and deeper paths', () {
      expect(AppRoutes.screenIn(Uri.parse('/')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/not-a-screen')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/minors/cs')), isNull);
    });

    test('round-trips every destination through its own path', () {
      for (final destination in AppDestinations.all) {
        final uri = Uri.parse(AppRoutes.pathFor(destination.screen));
        expect(uri.pathSegments, [destination.slug]);
      }
    });

    test('slugs are unique and URL-safe', () {
      final slugs = AppDestinations.all.map((d) => d.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
      for (final slug in slugs) {
        expect(slug, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')), reason: slug);
      }
    });
  });

  group('AppRoutes share links', () {
    test('reads the code out of a /s/<code> url', () {
      expect(AppRoutes.shareCodeIn(Uri.parse('https://tabulr.net/s/abc-123')),
          'abc-123');
    });

    test('is not fooled by other two-segment paths', () {
      expect(AppRoutes.shareCodeIn(Uri.parse('/courses/cs-f211')), isNull);
      expect(AppRoutes.shareCodeIn(Uri.parse('/s')), isNull);
      expect(AppRoutes.shareCodeIn(Uri.parse('/s/')), isNull);
    });

    test('accepts a pasted link or a bare code', () {
      const code = '5f2c9b1a-0000-4000-8000-abcdefabcdef';
      expect(AppRoutes.shareCodeInText('  https://tabulr.net/s/$code '), code);
      expect(AppRoutes.shareCodeInText(' $code '), code);
      expect(AppRoutes.shareCodeInText('   '), isNull);
    });
  });
}
