import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'campus_service.dart';
import 'local_cache_service.dart';
import '../../constants/app_constants.dart';

class CourseMasterEntry {
  final String courseCode;
  final String title;
  final double credits;
  final String type;

  CourseMasterEntry({
    required this.courseCode,
    required this.title,
    required this.credits,
    required this.type,
  });

  factory CourseMasterEntry.fromMap(Map<String, dynamic> map) {
    return CourseMasterEntry(
      courseCode: map['course_code'] ?? '',
      title: map['title'] ?? '',
      credits: (map['credits'] as num?)?.toDouble() ?? 0,
      type: map['type'] ?? 'Normal',
    );
  }
}

class CoursesMasterService {
  static final CoursesMasterService _instance = CoursesMasterService._();
  factory CoursesMasterService() => _instance;
  CoursesMasterService._();

  // Resolved on use rather than held as a field: this is a singleton, so an
  // eager initializer would demand Firebase be up the first time anything
  // touches the service — including code paths that only read the in-memory
  // cache and never go near Firestore.
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  final LocalCacheService _localCache = LocalCacheService();

  Map<String, CourseMasterEntry> _cache = {};
  bool _loaded = false;

  // The in-flight load, shared by concurrent callers. Without this a second
  // caller used to hit an `if (_loading) return` and get its `await` back
  // *before* the first load populated the cache — reading an empty catalogue.
  Future<void>? _inflight;

  final StreamController<bool> _loadStateController =
      StreamController<bool>.broadcast();

  Stream<bool> get loadStateStream => _loadStateController.stream;

  String get _cacheKey => 'courses_master_${CampusService.campusId}';

  /// Reads the single-document catalogue bundle. Returns null (so the caller
  /// falls back to the full collection scan) when it's missing, empty or
  /// unparseable — the bundle is an optimisation, never a hard dependency.
  Future<List<Map<String, dynamic>>?> _readBundle(String campusId) async {
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.campuses)
          .doc(campusId)
          .collection(FirestoreCollections.catalog)
          .doc(FirestoreCollections.coursesMasterBundle)
          .get()
          .timeout(AppDurations.startupReadTimeout);
      if (!doc.exists) return null;
      final raw = doc.data()?['entriesJson'] as String?;
      if (raw == null || raw.isEmpty) return null;
      final entries = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return entries.isEmpty ? null : entries;
    } catch (_) {
      return null;
    }
  }

  /// Test seam substituting the Firestore-backed load, so the single-flight
  /// coalescing can be exercised without Firebase. Never set from app code.
  @visibleForTesting
  Future<void> Function(bool forceRefresh)? loaderForTest;

  Future<void> loadForCampus({bool forceRefresh = false}) {
    if (_loaded && !forceRefresh) return Future.value();
    // Coalesce concurrent callers onto one load; whenComplete clears the slot
    // even on error, so a transient Firestore failure can't wedge it shut.
    return _inflight ??= (loaderForTest ?? _doLoad)(forceRefresh)
        .whenComplete(() => _inflight = null);
  }

  Future<void> _doLoad(bool forceRefresh) async {
    _loadStateController.add(false);
    final campusId = CampusService.campusId;

    if (!forceRefresh) {
      final cached = await _localCache.readIfFresh(
        _cacheKey,
        metadataRef: CampusService.metadataDocRef(_firestore),
      );
      if (cached != null) {
        _cache = {
          for (final map in cached)
            map['course_code'] as String: CourseMasterEntry.fromMap(map)
        };
        _loaded = true;
        _loadStateController.add(true);
        return;
      }
    }

    // Pre-bundled catalogue: 1 read instead of ~2.8k. Falls back to the
    // legacy per-document scan below if the bundle hasn't been generated yet.
    final bundled = await _readBundle(campusId);
    if (bundled != null) {
      _cache = {
        for (final map in bundled)
          map['course_code'] as String: CourseMasterEntry.fromMap(map)
      };
      await _localCache.write(_cacheKey, bundled);
      _loaded = true;
      _loadStateController.add(true);
      return;
    }

    final snapshot = await _firestore
        .collection(FirestoreCollections.campuses)
        .doc(campusId)
        .collection(FirestoreCollections.coursesMaster)
        .get()
        .timeout(AppDurations.startupReadTimeout);

    final docs = snapshot.docs.map((doc) => doc.data()).toList();
    _cache = {
      for (final map in docs)
        map['course_code'] as String: CourseMasterEntry.fromMap(map)
    };

    await _localCache.write(_cacheKey, docs);
    _loaded = true;
    _loadStateController.add(true);
  }

  String getTitle(String courseCode) {
    return _cache[courseCode]?.title ?? courseCode;
  }

  CourseMasterEntry? get(String courseCode) => _cache[courseCode];

  List<CourseMasterEntry> get allCourses => _cache.values.toList();

  bool get isLoaded => _loaded;

  void clear() {
    _cache = {};
    _loaded = false;
    _inflight = null;
    _localCache.invalidate(_cacheKey);
  }

  /// Fills the catalogue in-memory and marks it loaded, so widgets that read it
  /// can be tested without Firestore. Never call this from app code.
  @visibleForTesting
  void seedForTest(List<CourseMasterEntry> entries) {
    _cache = {for (final e in entries) e.courseCode: e};
    _loaded = true;
    _inflight = null;
  }

  /// Undoes [seedForTest] without touching the on-disk cache, which
  /// [clear] would try to reach.
  @visibleForTesting
  void resetForTest() {
    _cache = {};
    _loaded = false;
    _inflight = null;
  }
}
