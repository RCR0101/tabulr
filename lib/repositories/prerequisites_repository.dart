import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../services/ui/secure_logger.dart';
import '../constants/app_constants.dart';
import '../models/prerequisite.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/local_cache_service.dart';
import '../utils/course_code.dart';

/// Reads the prerequisite catalogue, cached in memory and on disk.
///
/// A singleton, like every service around it. It used to be a plain class, and
/// every call site wrote `PrerequisitesRepository()` — so the generator's prereq
/// warning and the prereq screen each got a fresh instance with an empty
/// in-memory cache, and re-read and re-deserialised the whole catalogue from
/// disk on every open. Sharing one instance makes the in-memory cache do the
/// job it was written for.
class PrerequisitesRepository {
  static final PrerequisitesRepository _instance =
      PrerequisitesRepository._internal();
  factory PrerequisitesRepository() => _instance;
  PrerequisitesRepository._internal();

  /// Test seam: substitute an in-memory Firestore so the real load paths can be
  /// exercised without a network. Never set from app code.
  ///
  /// Resolved on use rather than held as a field: an eager initializer demands
  /// Firebase be up the moment anything touches this class, including paths
  /// that only read the in-memory cache.
  @visibleForTesting
  FirebaseFirestore? firestoreForTest;

  FirebaseFirestore get _firestore =>
      firestoreForTest ?? FirebaseFirestore.instance;
  final LocalCacheService _localCache = LocalCacheService();

  static const _cacheKey = 'prerequisites';

  CollectionReference<Map<String, dynamic>> get _prereqsRef =>
      _firestore.collection(FirestoreCollections.reference).doc(FirestoreCollections.prerequisites).collection(FirestoreCollections.courses);

  /// Freshness marker for the local cache.
  ///
  /// Lives on the `reference/prerequisites` document — the parent of the
  /// `courses` subcollection this repository reads — so it is covered by the
  /// same rule (`match /reference/prerequisites/{sub=**}`): world-readable,
  /// admin-writable.
  ///
  /// It used to point at a top-level `metadata/prerequisites`, which no rule
  /// matches. Firestore denied it, `readIfFresh` caught the error and reported
  /// the cache as stale, and every prereq load fell through to a full scan of
  /// the collection — hundreds of document reads per load, for every user,
  /// while the persistent cache was never once used.
  DocumentReference<Map<String, dynamic>> get _metadataRef =>
      _firestore
          .collection(FirestoreCollections.reference)
          .doc(FirestoreCollections.prerequisites);

  List<CoursePrerequisites>? _cache;

  Future<List<CoursePrerequisites>> _loadAll() async {
    if (_cache != null) return _cache!;

    final cached = await _localCache.readIfFresh(
      _cacheKey,
      metadataRef: _metadataRef,
    );
    if (cached != null) {
      _cache = cached
          .map((m) => CoursePrerequisites.fromMap(m))
          .toList();
      return _cache!;
    }

    final snapshot = await _prereqsRef.get();
    final rawDocs = snapshot.docs.map((doc) => doc.data()).toList();
    _cache = rawDocs
        .map((m) => CoursePrerequisites.fromMap(m))
        .toList();
    await _localCache.write(_cacheKey, rawDocs);
    return _cache!;
  }

  void clearCache() {
    _cache = null;
    _localCache.invalidate(_cacheKey);
  }

  /// Drops the in-memory cache only, leaving the on-disk one intact.
  ///
  /// Exists so tests can exercise the persistent tier, which is otherwise
  /// unreachable once this became a singleton — the previous tests relied on
  /// constructing a second instance to get an empty in-memory cache.
  @visibleForTesting
  void resetInMemoryCache() => _cache = null;


  /// Create or replace a course's prerequisites (admin). Bumps the freshness
  /// marker so other devices refresh, and clears the local cache.
  Future<void> saveCoursePrerequisites(CoursePrerequisites course) async {
    await _prereqsRef.doc(courseCodeToDocId(course.courseCode)).set(course.toMap());
    await _bumpMetadata();
    clearCache();
  }

  Future<void> deleteCoursePrerequisites(String courseCode) async {
    await _prereqsRef.doc(courseCodeToDocId(courseCode)).delete();
    await _bumpMetadata();
    clearCache();
  }

  /// Best-effort freshness bump; the prereq doc write is the source of truth,
  /// so a failed metadata write must not fail the save. (This is now writable
  /// by admins — it was silently denied while the marker sat outside the rules.)
  Future<void> _bumpMetadata() async {
    try {
      await _metadataRef.set(
        {'lastUpdated': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (e) {
      SecureLogger.warning('PREREQ_REPO', 'Metadata freshness bump failed (non-fatal)', {'error': e.toString()});
    }
  }

  Future<List<CoursePrerequisites>> searchCourses(String query) async {
    if (query.isEmpty) return [];

    final lowercaseQuery = query.toLowerCase().trim();
    final all = await _loadAll();

    final results = all.where((course) {
      final codeLower = course.courseCode.toLowerCase();
      final titleLower = CoursesMasterService().getTitle(course.courseCode).toLowerCase();

      if (codeLower == lowercaseQuery) return true;
      if (codeLower.startsWith(lowercaseQuery)) return true;
      if (titleLower.contains(lowercaseQuery)) return true;
      return false;
    }).toList();

    results.sort((a, b) {
      final aCodeLower = a.courseCode.toLowerCase();
      final bCodeLower = b.courseCode.toLowerCase();

      final aExact = aCodeLower == lowercaseQuery;
      final bExact = bCodeLower == lowercaseQuery;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      final aStartsWith = aCodeLower.startsWith(lowercaseQuery);
      final bStartsWith = bCodeLower.startsWith(lowercaseQuery);
      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;

      return a.courseCode.compareTo(b.courseCode);
    });

    return results.take(25).toList();
  }

  Future<CoursePrerequisites?> getCoursePrerequisites(String courseCode) async {
    try {
      final docId = courseCodeToDocId(courseCode);
      final doc = await _prereqsRef.doc(docId).get();

      if (doc.exists) {
        return CoursePrerequisites.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<CoursePrerequisites>> getCoursesWithPrerequisites() async {
    final all = await _loadAll();
    return all.where((c) => c.hasPrerequisites).toList();
  }

  Future<List<CoursePrerequisites>> getAllCourses({int limit = 200}) async {
    final all = await _loadAll();
    return all.take(limit).toList();
  }

  Future<List<CoursePrerequisites>> getFilteredCourses({
    bool? hasPrerequisites,
    int limit = 100,
  }) async {
    final all = await _loadAll();
    var filtered = all.toList();
    if (hasPrerequisites != null) {
      filtered = filtered.where((c) => c.hasPrerequisites == hasPrerequisites).toList();
    }
    return filtered.take(limit).toList();
  }

  Future<List<CoursePrerequisites>> getCoursesByDepartment(
    String departmentCode,
    {int limit = 50}
  ) async {
    final deptLower = departmentCode.toLowerCase();
    final all = await _loadAll();
    return all
        .where((c) => c.courseCode.toLowerCase().startsWith('$deptLower '))
        .take(limit)
        .toList();
  }
}
