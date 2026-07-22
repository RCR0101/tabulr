import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';

void main() {
  group('AppDestinations', () {
    test('describes every screen the shell can show', () {
      // The switch in `of` is exhaustive, so this can only fail if someone
      // deletes a case — but it also documents the contract the sidebar and
      // the command palette both rely on.
      expect(AppDestinations.all.length, DrawerScreen.values.length);
      for (final screen in DrawerScreen.values) {
        expect(AppDestinations.of(screen).screen, screen);
      }
    });

    test('keeps navigation order', () {
      expect(
        AppDestinations.all.map((d) => d.screen),
        DrawerScreen.values,
      );
    });

    test('every destination is labelled and described', () {
      // An empty description would leave a palette row with nothing to search
      // beyond its title.
      for (final destination in AppDestinations.all) {
        expect(destination.label, isNotEmpty, reason: '${destination.screen}');
        expect(destination.description, isNotEmpty,
            reason: '${destination.screen}');
      }
    });

    test('labels are unique', () {
      // The palette dedupes recents by label, and two rows reading the same
      // would be indistinguishable.
      final labels = AppDestinations.all.map((d) => d.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('the public screens are the ones open to guests', () {
      final open = AppDestinations.all
          .where((d) => d.access == DestinationAccess.everyone)
          .map((d) => d.screen)
          .toSet();
      expect(
        open,
        {
          DrawerScreen.timetables,
          DrawerScreen.examSeating,
          // The Bulletin and the regulations are public.
          DrawerScreen.minors,
          DrawerScreen.faq,
        },
      );
    });

    test('admin and Hyderabad screens are gated to exactly one screen each', () {
      expect(
        AppDestinations.all
            .where((d) => d.access == DestinationAccess.admin)
            .map((d) => d.screen),
        [DrawerScreen.admin],
      );
      expect(
        AppDestinations.all
            .where((d) => d.access == DestinationAccess.hyderabad)
            .map((d) => d.screen),
        [DrawerScreen.announcements],
      );
    });

    test('a guest sees only the open destinations', () {
      // isVisible reads the auth singletons, which are signed out under test.
      expect(
        AppDestinations.visible.map((d) => d.screen).toSet(),
        AppDestinations.all
            .where((d) => d.access == DestinationAccess.everyone)
            .map((d) => d.screen)
            .toSet(),
      );
    });
  });
}
