// Mocktail must implement Firestore's sealed CollectionReference/
// DocumentReference to stub the read chain — expected and safe in tests.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/services/data/courses_master_service.dart';

/// Startup-stall regression for [CoursesMasterService].
///
/// The loading fix wrapped every startup Firestore read in
/// `.timeout(AppDurations.startupReadTimeout)` so a request that *stalls*
/// without erroring (observed on privacy-hardened browsers) can't block the
/// first frame. Here a Firestore whose reads never complete is injected, and
/// virtual time is advanced past the timeout: the load must resolve (throw a
/// TimeoutException) rather than hang, and the in-flight slot must clear so a
/// later attempt can still run.
class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  final service = CoursesMasterService();

  tearDown(() {
    service.firestoreForTest = null;
    service.resetForTest();
  });

  /// A Firestore whose bundle read and full-collection scan both hang forever.
  _MockFirestore hangingFirestore() {
    final firestore = _MockFirestore();
    final campuses = _MockCollection();
    final campusDoc = _MockDocument();
    final coursesMaster = _MockCollection();
    final catalog = _MockCollection();
    final bundleDoc = _MockDocument();

    when(() => firestore.collection('campuses')).thenReturn(campuses);
    when(() => campuses.doc(any())).thenReturn(campusDoc);
    when(() => campusDoc.collection('courses_master')).thenReturn(coursesMaster);
    when(() => campusDoc.collection('catalog')).thenReturn(catalog);
    when(() => catalog.doc(any())).thenReturn(bundleDoc);

    // Never-completing reads: the timeout must be what ends them.
    when(() => bundleDoc.get()).thenAnswer(
        (_) => Completer<DocumentSnapshot<Map<String, dynamic>>>().future);
    when(() => coursesMaster.get()).thenAnswer(
        (_) => Completer<QuerySnapshot<Map<String, dynamic>>>().future);

    return firestore;
  }

  test('a stalled read is bounded by the timeout, not left to hang', () {
    fakeAsync((async) {
      service.resetForTest();
      service.firestoreForTest = hangingFirestore();

      Object? error;
      var settled = false;
      service.loadForCampus(forceRefresh: true).then((_) {
        settled = true;
      }, onError: (Object e) {
        error = e;
        settled = true;
      });

      // Before the timeout fires, the load is genuinely pending.
      async.elapse(AppDurations.startupReadTimeout ~/ 2);
      expect(settled, isFalse, reason: 'should still be waiting pre-timeout');

      // Advance well past both reads' timeouts (bundle, then scan).
      async.elapse(AppDurations.startupReadTimeout * 3);
      expect(settled, isTrue, reason: 'timeout must end the stalled load');
      expect(error, isA<TimeoutException>());
    });
  });

  test('after a stalled load times out, the slot is free for a retry', () {
    fakeAsync((async) {
      service.resetForTest();
      service.firestoreForTest = hangingFirestore();

      service.loadForCampus(forceRefresh: true).catchError((_) {});
      async.elapse(AppDurations.startupReadTimeout * 3);
      async.flushMicrotasks();

      // The failed load must not have marked the service loaded nor wedged it.
      expect(service.isLoaded, isFalse);

      var retried = false;
      service.loadForCampus(forceRefresh: true).catchError((_) {
        retried = true; // a fresh run really started (and timed out again)
        return;
      });
      async.elapse(AppDurations.startupReadTimeout * 3);
      expect(retried, isTrue, reason: 'slot wedged: retry never ran');
    });
  });
}
