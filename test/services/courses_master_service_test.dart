import 'dart:async';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/services/data/campus_service.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';
import '../helpers/fake_path_provider.dart';
import '../helpers/test_reporter.dart';

/// Everything that guards [CoursesMasterService]'s single shared catalogue:
/// the single-flight loader (pinned interleavings, then randomised ones) and
/// the campus-switch race that used to publish a stale campus's courses.
void main() {
  // clear()/resetForTest invalidate the local cache, which touches the
  // filesystem via path_provider.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  installFakePathProvider('tabulr_courses_master');

  // Shared singleton — reset the test seams and cache around every case so one
  // test can't leak an in-flight loader, a fake Firestore or a loaded flag
  // into the next.
  final service = CoursesMasterService();
  final results = <Map<String, dynamic>>[];
  void record(String name, bool passed, int ms, [String? error]) {
    results.add({
      'name': name,
      'status': passed ? 'pass' : 'fail',
      'duration_ms': ms,
      if (error != null) 'error': error,
    });
  }

  tearDown(() {
    service.loaderForTest = null;
    service.firestoreForTest = null;
    service.resetForTest();
  });

  tearDownAll(() async {
    await TestReporter.reportTestResults('courses_master', results);
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

  group('single-flight under randomised interleavings', () {
    // A loader whose every invocation hands back a completer the test resolves
    // by hand, so interleavings are exact and deterministic.
    ({int Function() runs, List<Completer<void>> pending}) installLoader() {
      var runs = 0;
      final pending = <Completer<void>>[];
      service.loaderForTest = (_) {
        runs++;
        final c = Completer<void>();
        pending.add(c);
        return c.future;
      };
      return (runs: () => runs, pending: pending);
    }

    test('random interleavings preserve single-flight + no-hang + no-wedge',
        () async {
      final sw = Stopwatch()..start();
      const trials = 400;
      try {
        for (var t = 0; t < trials; t++) {
          final r = Random(0xF00D + t);
          service.resetForTest();
          final loader = installLoader();
          var expectedRuns = 0;

          // ── Batch 1: several concurrent callers, fired before any resolve.
          // Not loaded yet, so all coalesce onto one run.
          final batch1 = <Future<void>>[];
          final k1 = 2 + r.nextInt(5);
          for (var i = 0; i < k1; i++) {
            batch1.add(service.loadForCampus());
          }
          expectedRuns++; // one coalesced run
          expect(loader.runs(), expectedRuns, reason: 'trial=$t batch1 coalesce');
          expect(loader.pending.length, 1, reason: 'trial=$t one in-flight');

          // ── Late joiners while still in-flight also coalesce.
          final k2 = r.nextInt(4);
          for (var i = 0; i < k2; i++) {
            batch1.add(service.loadForCampus(forceRefresh: r.nextBool()));
          }
          expect(loader.runs(), expectedRuns,
              reason: 'trial=$t late joiners must not start a new run');

          // ── Resolve the single in-flight load: succeed or fail.
          final fail = r.nextBool();
          if (fail) {
            loader.pending.single.completeError(StateError('boom$t'));
            for (final f in batch1) {
              await expectLater(f.timeout(const Duration(seconds: 2)),
                  throwsA(isA<StateError>()),
                  reason: 'trial=$t every coalesced caller sees the error');
            }
          } else {
            loader.pending.single.complete();
            await Future.wait(batch1).timeout(const Duration(seconds: 2));
          }

          // loaderForTest never sets _loaded, so we are still "not loaded".
          expect(service.isLoaded, isFalse, reason: 'trial=$t seam leaves unloaded');

          // ── Slot must be free: a fresh call starts a brand-new run.
          final after = service.loadForCampus();
          expectedRuns++;
          expect(loader.runs(), expectedRuns,
              reason: 'trial=$t slot not freed after ${fail ? 'error' : 'success'}');
          loader.pending.last.complete();
          await after.timeout(const Duration(seconds: 2));

          // ── Randomly clear() and confirm the next load still runs (no wedge).
          if (r.nextBool()) {
            service.clear();
            expect(service.isLoaded, isFalse, reason: 'trial=$t clear resets');
            final post = service.loadForCampus(forceRefresh: true);
            expectedRuns++;
            expect(loader.runs(), expectedRuns,
                reason: 'trial=$t wedged after clear()');
            loader.pending.last.complete();
            await post.timeout(const Duration(seconds: 2));
          }

          // ── Loaded short-circuit: once seeded, a non-forced load must not run.
          if (r.nextBool()) {
            service.seedForTest(const []);
            expect(service.isLoaded, isTrue);
            final runsBefore = loader.runs();
            await service.loadForCampus().timeout(const Duration(seconds: 2));
            expect(loader.runs(), runsBefore,
                reason: 'trial=$t loaded non-forced load must short-circuit');
          }
        }
        sw.stop();
        record('random interleavings', true, sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        record('random interleavings', false, sw.elapsedMilliseconds, e.toString());
        rethrow;
      }
    });
  });

  group('campus-switch race', () {
    // A campus switch clears the catalogue and starts a new load. If the *old*
    // campus's load is slower and resolves after the switch, committing it would
    // overwrite the new campus's catalogue (and persist it under the new
    // campus's cache key). _commit now drops a result whose campus no longer
    // matches. The race is forced deterministically: start a load, then flip the
    // campus synchronously while the in-memory Firestore read is still pending.
    setUp(() async {
      service.resetForTest();
      final fake = FakeFirebaseFirestore();
      // Two campuses, each with a distinct single-course catalogue.
      await fake
          .collection('campuses')
          .doc('hyderabad')
          .collection('courses_master')
          .doc('c1')
          .set({'course_code': 'HYD_ONLY', 'title': 'Hyderabad Course'});
      await fake
          .collection('campuses')
          .doc('pilani')
          .collection('courses_master')
          .doc('c2')
          .set({'course_code': 'PIL_ONLY', 'title': 'Pilani Course'});
      service.firestoreForTest = fake;
      await CampusService.setCampus(Campus.hyderabad);
    });

    tearDown(() {
      service.firestoreForTest = null;
      service.resetForTest();
    });

    test('a load that finishes while its campus is current commits normally',
        () async {
      await service.loadForCampus(forceRefresh: true);
      expect(service.isLoaded, isTrue);
      expect(service.getTitle('HYD_ONLY'), 'Hyderabad Course');
    });

    test('a stale load resolving after a campus switch is dropped', () async {
      // Start the Hyderabad load; it suspends on the in-memory Firestore read.
      final stale = service.loadForCampus(forceRefresh: true);
      // Switch to Pilani *before* the read resolves — _currentCampus flips
      // synchronously, so when the Hyderabad read lands its commit is stale.
      final switching = CampusService.setCampus(Campus.pilani);
      await Future.wait([stale, switching]);

      // The stale Hyderabad catalogue must not have been published.
      expect(service.isLoaded, isFalse,
          reason: 'stale load must not mark the service loaded');
      expect(service.getTitle('HYD_ONLY'), 'HYD_ONLY',
          reason: 'stale campus data must not populate the cache');
    });

    test('after the stale drop, a fresh Pilani load still succeeds', () async {
      final stale = service.loadForCampus(forceRefresh: true);
      final switching = CampusService.setCampus(Campus.pilani);
      await Future.wait([stale, switching]);

      // The slot is free and the guard doesn't wedge future loads.
      await service.loadForCampus(forceRefresh: true);
      expect(service.isLoaded, isTrue);
      expect(service.getTitle('PIL_ONLY'), 'Pilani Course');
      expect(service.getTitle('HYD_ONLY'), 'HYD_ONLY');
    });
  });

  group('credit hours', () {
    test('a course published only in hours reports them, not 0U', () {
      // credits alone is 0 for these, which rendered as "0U" in the course
      // guide and the CGPA picker, and weighted the course as nothing wherever
      // it was summed.
      final chem = CourseMasterEntry.fromMap({
        'course_code': 'CHEM U101',
        'title': 'Atomic Structure',
        'credits': 0,
        'credit_hours': 7,
        'type': 'Normal',
      });
      expect(chem.isInCreditHours, isTrue);
      expect(chem.effectiveCredits, 7);

      final cs = CourseMasterEntry.fromMap({
        'course_code': 'CS F211',
        'title': 'Data Structures',
        'credits': 4,
        'type': 'Normal',
      });
      expect(cs.isInCreditHours, isFalse);
      expect(cs.effectiveCredits, 4);
      expect(cs.creditHours, 0);
    });
  });
}
