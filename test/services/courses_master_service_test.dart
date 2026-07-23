import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';

void main() {
  // Shared singleton — reset the test seam and cache around every case so one
  // test can't leak an in-flight loader or a loaded flag into the next.
  final service = CoursesMasterService();

  tearDown(() {
    service.loaderForTest = null;
    service.resetForTest();
  });

  group('loadForCampus single-flight', () {
    test('concurrent callers coalesce onto one load', () async {
      var calls = 0;
      final gate = Completer<void>();
      service.loaderForTest = (_) async {
        calls++;
        await gate.future;
      };

      final a = service.loadForCampus();
      final b = service.loadForCampus();

      // The second caller must not have kicked off a second load...
      expect(calls, 1);

      gate.complete();
      await Future.wait([a, b]);

      // ...and awaiting either returns only once the single load finished.
      expect(calls, 1);
    });

    test('a fresh load can start once the in-flight one is done', () async {
      var calls = 0;
      service.loaderForTest = (_) async => calls++;

      await service.loadForCampus();
      await service.loadForCampus();

      // Neither call set _loaded (the seam doesn't), so both really ran — the
      // in-flight slot was cleared after the first completed.
      expect(calls, 2);
    });

    test('a load error clears the slot instead of wedging it shut', () async {
      var calls = 0;
      service.loaderForTest = (_) async {
        calls++;
        throw StateError('boom');
      };

      await expectLater(service.loadForCampus(), throwsStateError);
      // A transient failure must not leave every later attempt a no-op.
      await expectLater(service.loadForCampus(), throwsStateError);
      expect(calls, 2);
    });

    test('once loaded, a non-forced load short-circuits without loading',
        () async {
      var calls = 0;
      service.loaderForTest = (_) async => calls++;
      service.seedForTest(const []);

      await service.loadForCampus();
      expect(calls, 0);

      await service.loadForCampus(forceRefresh: true);
      expect(calls, 1);
    });
  });
}
