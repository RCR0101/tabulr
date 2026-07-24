import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';
import '../helpers/test_reporter.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// Concurrency stress for [CoursesMasterService]'s single-flight loader.
///
/// courses_master_service_test.dart pins four specific interleavings; this
/// fuzzes hundreds of random ones — batches of concurrent callers that coalesce
/// onto one load, resolutions that succeed or throw, `clear()` landing between
/// batches, and the loaded-short-circuit — and asserts the invariants that must
/// hold for every interleaving:
///   * concurrent callers before a resolution share exactly one loader run;
///   * every caller settles (never hangs) with the shared result;
///   * a completed or failed load always frees the slot (never wedges);
///   * `clear()` mid-flight never resurrects state or wedges the next load.
void main() {
  // clear()/resetForTest invalidate the local cache, which touches the
  // filesystem via path_provider — point it at a throwaway temp dir so it
  // doesn't warn about a missing platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('tabulr_cmc').path);

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
    service.resetForTest();
  });

  tearDownAll(() async {
    await TestReporter.reportTestResults(
        'courses_master_concurrency', results);
  });

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
}
