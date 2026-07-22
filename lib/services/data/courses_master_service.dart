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
  bool _loading = false;

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
          .get();
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

  Future<void> loadForCampus({bool forceRefresh = false}) async {
    if (_loading) return;
    if (_loaded && !forceRefresh) return;
    _loading = true;
    _loadStateController.add(false);

    // finally, not a trailing assignment: a throw anywhere below used to leave
    // _loading stuck true, and the `if (_loading) return` guard above then made
    // every later attempt a no-op — one transient Firestore error left the
    // catalogue permanently empty for the rest of the session.
    try {
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
          .get();

      final docs = snapshot.docs.map((doc) => doc.data()).toList();
      _cache = {
        for (final map in docs)
          map['course_code'] as String: CourseMasterEntry.fromMap(map)
      };

      await _localCache.write(_cacheKey, docs);
      _loaded = true;
      _loadStateController.add(true);
    } finally {
      _loading = false;
    }
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
    _loading = false;
    _localCache.invalidate(_cacheKey);
  }

  /// Fills the catalogue in-memory and marks it loaded, so widgets that read it
  /// can be tested without Firestore. Never call this from app code.
  @visibleForTesting
  void seedForTest(List<CourseMasterEntry> entries) {
    _cache = {for (final e in entries) e.courseCode: e};
    _loaded = true;
    _loading = false;
  }

  /// Undoes [seedForTest] without touching the on-disk cache, which
  /// [clear] would try to reach.
  @visibleForTesting
  void resetForTest() {
    _cache = {};
    _loaded = false;
    _loading = false;
  }
}
