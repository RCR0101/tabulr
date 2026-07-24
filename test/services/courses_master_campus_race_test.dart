import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/services/data/campus_service.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';

/// Regression test for the campus-switch race in [CoursesMasterService].
///
/// A campus switch clears the catalogue and starts a new load. If the *old*
/// campus's load is slower and resolves after the switch, committing it would
/// overwrite the new campus's catalogue (and persist it under the new campus's
/// cache key). [_commit] now drops a result whose campus no longer matches. We
/// force the race deterministically: start a load, then flip the campus
/// synchronously (CampusService sets its field before any await) while the
/// in-memory Firestore read is still pending.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('tabulr_race').path);

  final service = CoursesMasterService();

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
}
