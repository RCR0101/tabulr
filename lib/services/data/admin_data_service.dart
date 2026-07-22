import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';

class AdminDataService {
  static final AdminDataService _instance = AdminDataService._internal();
  factory AdminDataService() => _instance;
  AdminDataService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _timetableRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection('timetable');

  CollectionReference<Map<String, dynamic>> _masterRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.coursesMaster);

  CollectionReference<Map<String, dynamic>> _examRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.examSeating);

  CollectionReference<Map<String, dynamic>> _profsRef(String campusId) =>
      _db.collection(FirestoreCollections.reference).doc(FirestoreCollections.professors).collection('$campusId-entries');

  // ── Per-campus row cache ──
  //
  // The admin search fields call these fetchers on a 400ms debounce — i.e.
  // roughly per keystroke. Each call used to re-scan whole collections
  // (fetchCourses alone reads timetable + courses_master, ~3.3k docs) even
  // though filtering already happens in memory. Load once per campus, then
  // filter locally; mutations invalidate the affected set.
  final Map<String, List<Map<String, dynamic>>> _rowCache = {};

  static String _key(String kind, String campusId) => '$kind:$campusId';

  void _invalidate(String kind, String campusId) =>
      _rowCache.remove(_key(kind, campusId));

  /// Drops every cached row set (e.g. after a bulk upload changed data
  /// underneath us).
  void invalidateAll() => _rowCache.clear();

  Future<List<Map<String, dynamic>>> _rows(
    String kind,
    String campusId,
    bool forceRefresh,
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    final key = _key(kind, campusId);
    final cached = _rowCache[key];
    if (cached != null && !forceRefresh) return cached;
    final rows = await load();
    _rowCache[key] = rows;
    return rows;
  }

  /// Copies rows out of the cache so callers (edit dialogs) can mutate freely
  /// without corrupting it.
  static List<Map<String, dynamic>> _copy(Iterable<Map<String, dynamic>> rows) =>
      rows.map((r) => Map<String, dynamic>.from(r)).toList();

  // ── Courses ──

  Future<List<Map<String, dynamic>>> fetchCourses(
    String campusId, {
    String? query,
    bool forceRefresh = false,
  }) async {
    final rows = await _rows('courses', campusId, forceRefresh, () async {
      final timetableSnap = await _timetableRef(campusId).get();
      final masterSnap = await _masterRef(campusId).get();
      final masterMap = {for (final d in masterSnap.docs) d.id: d.data()};

      final all = <Map<String, dynamic>>[];
      for (final doc in timetableSnap.docs) {
        final master = masterMap[doc.id];
        all.add({
          'docId': doc.id,
          ...doc.data(),
          'course_code': master?['course_code'] ?? doc.id.replaceAll('_', ' '),
          'title': master?['title'] ?? '',
          'credits': master?['credits'] ?? 0,
          'type': master?['type'] ?? 'Normal',
        });
      }
      all.sort((a, b) =>
          (a['course_code'] as String).compareTo(b['course_code'] as String));
      return all;
    });

    if (query == null || query.isEmpty) return _copy(rows);
    final q = query.toLowerCase();
    return _copy(rows.where((data) {
      final code = (data['course_code'] as String).toLowerCase();
      final title = (data['title'] as String).toLowerCase();
      return code.contains(q) || title.contains(q);
    }));
  }

  Future<void> saveCourse(String campusId, {
    required String docId,
    required Map<String, dynamic> timetableData,
    required Map<String, dynamic> masterData,
  }) async {
    final batch = _db.batch();
    batch.set(_timetableRef(campusId).doc(docId), timetableData);
    batch.set(_masterRef(campusId).doc(docId), masterData);
    await batch.commit();
    _invalidate('courses', campusId);
    await _syncCatalogBundle(campusId, upsert: masterData);
  }

  Future<void> deleteCourse(String campusId, String docId) async {
    final batch = _db.batch();
    batch.delete(_timetableRef(campusId).doc(docId));
    batch.delete(_masterRef(campusId).doc(docId));
    await batch.commit();
    _invalidate('courses', campusId);
    await _syncCatalogBundle(campusId, removeDocId: docId);
  }

  DocumentReference<Map<String, dynamic>> _bundleRef(String campusId) => _db
      .collection(FirestoreCollections.campuses)
      .doc(campusId)
      .collection(FirestoreCollections.catalog)
      .doc(FirestoreCollections.coursesMasterBundle);

  static String _normalizeCode(String code) =>
      code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  /// Keeps the single-document catalogue bundle in sync after an in-app course
  /// edit.
  ///
  /// The app reads that bundle on cold start instead of the ~2.8k
  /// courses_master documents. The client only falls back to the full scan when
  /// the bundle is *missing* — a **stale** bundle would silently hide this
  /// edit, so failures here deliberately propagate rather than being swallowed.
  /// Patching costs 1 read + 1 write instead of rebuilding from scratch.
  Future<void> _syncCatalogBundle(
    String campusId, {
    Map<String, dynamic>? upsert,
    String? removeDocId,
  }) async {
    final ref = _bundleRef(campusId);
    final snap = await ref.get();
    // No bundle yet — the bulk uploader will create it; nothing to keep in sync.
    if (!snap.exists) return;
    final raw = snap.data()?['entriesJson'] as String?;
    if (raw == null || raw.isEmpty) return;

    final entries = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (removeDocId != null) {
      entries.removeWhere(
          (e) => _normalizeCode(e['course_code'] as String? ?? '') == removeDocId);
    }

    if (upsert != null) {
      final code = upsert['course_code'] as String? ?? '';
      if (code.isEmpty) return;
      final entry = <String, dynamic>{
        'course_code': code,
        'title': upsert['title'] ?? '',
        'credits': (upsert['credits'] as num?) ?? 0,
        'type': upsert['type'] ?? 'Normal',
      };
      final index = entries.indexWhere((e) => e['course_code'] == code);
      if (index >= 0) {
        entries[index] = entry;
      } else {
        entries.add(entry);
      }
      entries.sort((a, b) =>
          (a['course_code'] as String).compareTo(b['course_code'] as String));
    }

    final stamp = DateTime.now();
    await ref.set({
      'version': stamp.toIso8601String(),
      'count': entries.length,
      'entriesJson': jsonEncode(entries),
    });

    // Clients only re-read the catalogue when campus metadata says it's newer,
    // so bump it or this edit stays invisible behind their local cache.
    await _db
        .collection(FirestoreCollections.campuses)
        .doc(campusId)
        .collection(FirestoreCollections.metadata)
        .doc(FirestoreCollections.current)
        .set({
      'lastUpdated': stamp.toIso8601String(),
      'version': stamp.millisecondsSinceEpoch.toString(),
    }, SetOptions(merge: true));
  }

  // ── Exam Seating ──

  Future<List<Map<String, dynamic>>> fetchExamSeating(
    String campusId, {
    String? query,
    bool forceRefresh = false,
  }) async {
    final rows = await _rows('exam', campusId, forceRefresh, () async {
      final snap = await _examRef(campusId).get();
      final all = [
        for (final doc in snap.docs) {'docId': doc.id, ...doc.data()}
      ];
      all.sort((a, b) => (a['docId'] as String).compareTo(b['docId'] as String));
      return all;
    });

    if (query == null || query.isEmpty) return _copy(rows);
    final q = query.toLowerCase();
    return _copy(
        rows.where((data) => (data['docId'] as String).toLowerCase().contains(q)));
  }

  Future<void> saveExamSeating(String campusId, String docId, Map<String, dynamic> data) async {
    await _examRef(campusId).doc(docId).set(data);
    _invalidate('exam', campusId);
  }

  Future<void> deleteExamSeating(String campusId, String docId) async {
    await _examRef(campusId).doc(docId).delete();
    _invalidate('exam', campusId);
  }

  // ── Professors ──

  Future<List<Map<String, dynamic>>> fetchProfessors(
    String campusId, {
    String? query,
    bool forceRefresh = false,
  }) async {
    final rows = await _rows('profs', campusId, forceRefresh, () async {
      final snap = await _profsRef(campusId).get();
      final all = [
        for (final doc in snap.docs) {'docId': doc.id, ...doc.data()}
      ];
      all.sort((a, b) => (a['name'] as String? ?? '')
          .compareTo(b['name'] as String? ?? ''));
      return all;
    });

    if (query == null || query.isEmpty) return _copy(rows);
    final q = query.toLowerCase();
    return _copy(rows.where((data) {
      final name = (data['name'] as String? ?? '').toLowerCase();
      final chamber = (data['chamber'] as String? ?? '').toLowerCase();
      return name.contains(q) || chamber.contains(q);
    }));
  }

  Future<void> saveProfessor(String campusId, String docId, Map<String, dynamic> data) async {
    await _profsRef(campusId).doc(docId).set(data, SetOptions(merge: true));
    _invalidate('profs', campusId);
  }

  Future<void> deleteProfessor(String campusId, String docId) async {
    await _profsRef(campusId).doc(docId).delete();
    _invalidate('profs', campusId);
  }
}
