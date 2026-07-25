import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timetable_maker/repositories/prerequisites_repository.dart';
import 'package:timetable_maker/services/data/local_cache_service.dart';

/// The prerequisites load path, and specifically whether its cache works.
///
/// This test could not exist before the repository had a Firestore seam, and
/// that absence is why the cache stayed broken: the freshness marker pointed at
/// a top-level `metadata/prerequisites`, which no security rule matches.
/// Firestore denied the read, LocalCacheService.readIfFresh caught the error and
/// reported "stale", and every load fell through to a full collection scan —
/// hundreds of reads per user, the persistent cache never once used, nothing
/// raising.
///
/// The cache assertions delete the collection between loads. Asserting only on
/// the returned data would pass whether or not the cache was used; a load that
/// still succeeds against an empty collection can only have come from cache.
///
/// The repository is a singleton, so resetInMemoryCache() is what forces a read
/// through to the persistent tier — constructing a second instance no longer
/// gives an empty in-memory cache.

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tempDir;

  // One directory for the whole file, not one per test: LocalCacheService is a
  // singleton that memoizes its cache directory on first use, so re-pointing
  // path_provider per test left it writing into an already-deleted path and
  // every cache read silently missed.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('prereq_cache_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await LocalCacheService().invalidate('prerequisites');
    PrerequisitesRepository().resetInMemoryCache();
  });

  CollectionReference<Map<String, dynamic>> coursesOf(
          FakeFirebaseFirestore db) =>
      db.collection('reference').doc('prerequisites').collection('courses');

  Future<void> addCourse(FakeFirebaseFirestore db, String code) async {
    // Matches CoursePrerequisites.toMap(): groups is a list of MAPS, each with
    // an `options` list. Firestore forbids nested arrays, so the AND-of-ORs
    // shape has to be carried by that intermediate map rather than [[...]].
    await coursesOf(db).doc(code.replaceAll(' ', '_')).set({
      'course_code': code,
      'has_prerequisites': true,
      'groups': [
        {
          'options': [
            {'course_code': 'CS F111', 'type': 'pre'}
          ]
        }
      ],
    });
  }

  Future<void> bumpMarker(FakeFirebaseFirestore db, {DateTime? at}) async {
    await db.collection('reference').doc('prerequisites').set(
      {'lastUpdated': (at ?? DateTime.now()).toIso8601String()},
      SetOptions(merge: true),
    );
  }

  Future<FakeFirebaseFirestore> seed({int courses = 40}) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < courses; i++) {
      await addCourse(db, 'CS F${100 + i}');
    }
    await bumpMarker(db);
    return db;
  }

  test('the freshness marker lives on the parent of the courses collection',
      () async {
    // Not a top-level `metadata` collection: firestore.rules covers
    // `reference/prerequisites/**` and has no rule for `metadata`, so a marker
    // there is unreadable in production even though a fake accepts it.
    final db = await seed(courses: 3);
    final marker = await db.collection('reference').doc('prerequisites').get();

    expect(marker.exists, isTrue);
    expect(marker.data()!['lastUpdated'], isNotNull);
  });

  test('a second load is served from cache, not another collection scan',
      () async {
    final db = await seed(courses: 40);
    final repo = PrerequisitesRepository()..firestoreForTest = db;
    expect((await repo.getCoursesWithPrerequisites()).length, 40);

    // Wipe the source and drop the in-memory tier. Anything returned now can
    // only have come off disk.
    for (final d in (await coursesOf(db).get()).docs) {
      await d.reference.delete();
    }
    repo.resetInMemoryCache();

    expect((await repo.getCoursesWithPrerequisites()).length, 40,
        reason: 'the persistent cache was not used');
  });

  test('a bumped marker invalidates the cache', () async {
    final db = await seed(courses: 5);
    final repo = PrerequisitesRepository()..firestoreForTest = db;
    expect((await repo.getCoursesWithPrerequisites()).length, 5);

    await addCourse(db, 'CS F999');
    await bumpMarker(db, at: DateTime.now().add(const Duration(hours: 1)));
    repo.resetInMemoryCache();

    expect((await repo.getCoursesWithPrerequisites()).length, 6,
        reason: 'a newer marker must force a refetch');
  });

  test('an unbumped marker keeps serving the cache', () async {
    final db = await seed(courses: 5);
    final repo = PrerequisitesRepository()..firestoreForTest = db;
    expect((await repo.getCoursesWithPrerequisites()).length, 5);

    // New course, marker untouched: the client has no way to know, and must
    // keep its cache rather than rescanning on every load.
    await addCourse(db, 'CS F999');
    repo.resetInMemoryCache();

    expect((await repo.getCoursesWithPrerequisites()).length, 5);
  });
}
