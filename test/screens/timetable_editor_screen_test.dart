import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/timetable_editor_screen.dart';

import '../helpers/test_data.dart';

void main() {
  group('background timetable refresh', () {
    test('applies while the original timetable is still clean', () {
      final timetable = makeTimetable();

      expect(
        canApplyBackgroundTimetableRefresh(
          currentTimetable: timetable,
          timetableAtRequestStart: timetable,
          hasUnsavedChanges: false,
        ),
        isTrue,
      );
    });

    test('does not replace a timetable with unsaved changes', () {
      final timetable = makeTimetable();

      expect(
        canApplyBackgroundTimetableRefresh(
          currentTimetable: timetable,
          timetableAtRequestStart: timetable,
          hasUnsavedChanges: true,
        ),
        isFalse,
      );
    });

    test(
      'does not replace a timetable changed while the request was running',
      () {
        final timetableAtRequestStart = makeTimetable(id: 'old');
        final currentTimetable = makeTimetable(id: 'new');

        expect(
          canApplyBackgroundTimetableRefresh(
            currentTimetable: currentTimetable,
            timetableAtRequestStart: timetableAtRequestStart,
            hasUnsavedChanges: false,
          ),
          isFalse,
        );
      },
    );
  });
}
