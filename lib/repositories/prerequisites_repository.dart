import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';
import '../models/prerequisite.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/local_cache_service.dart';

class PrerequisitesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalCacheService _localCache = LocalCacheService();

  static const _cacheKey = 'prerequisites';

  CollectionReference<Map<String, dynamic>> get _prereqsRef =>
      _firestore.collection(FirestoreCollections.reference).doc(FirestoreCollections.prerequisites).collection(FirestoreCollections.courses);

  DocumentReference<Map<String, dynamic>> get _metadataRef =>
      _firestore.collection('metadata').doc('prerequisites');

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

  static String _docId(String courseCode) => courseCode.replaceAll(' ', '_');

  /// Create or replace a course's prerequisites (admin). Bumps the freshness
  /// marker so other devices refresh, and clears the local cache.
  Future<void> saveCoursePrerequisites(CoursePrerequisites course) async {
    await _prereqsRef.doc(_docId(course.courseCode)).set(course.toMap());
    await _bumpMetadata();
    clearCache();
  }

  Future<void> deleteCoursePrerequisites(String courseCode) async {
    await _prereqsRef.doc(_docId(courseCode)).delete();
    await _bumpMetadata();
    clearCache();
  }

  /// Best-effort freshness bump; the prereq doc write is the source of truth,
  /// so a denied metadata write must not fail the save.
  Future<void> _bumpMetadata() async {
    try {
      await _metadataRef.set(
        {'lastUpdated': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (_) {}
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
      final docId = courseCode.replaceAll(' ', '_');
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
