import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../constants/app_constants.dart';
import '../../utils/course_code.dart';

class AdminDataService {
  static final AdminDataService _instance = AdminDataService._internal();
  factory AdminDataService() => _instance;
  AdminDataService._internal();

  /// Test seam: substitute an in-memory Firestore. Never set from app code.
  @visibleForTesting
  FirebaseFirestore? firestoreForTest;

  /// Resolved on use, not held as a field. This is a singleton, so an eager
  /// initializer demanded Firebase be up merely to *construct* the service —
  /// which threw before any `try` could catch it, and made every widget test
  /// that transitively reached an admin screen impossible.
  FirebaseFirestore get _db => firestoreForTest ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _timetableRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.timetable);

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
          'course_code': master?['course_code'] ?? docIdToCourseCode(doc.id),
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
    _invalidate('master', campusId);
    await _syncCatalogBundle(campusId, removeCode: docIdToCourseCode(docId));
  }

  DocumentReference<Map<String, dynamic>> _bundleRef(String campusId) => _db
      .collection(FirestoreCollections.campuses)
      .doc(campusId)
      .collection(FirestoreCollections.catalog)
      .doc(FirestoreCollections.coursesMasterBundle);

  /// Keeps the single-document catalogue bundle in sync after an in-app course
  /// edit.
  ///
  /// The app reads that bundle on cold start instead of the ~2.8k
  /// courses_master documents. The client only falls back to the full scan when
  /// the bundle is *missing* — a **stale** bundle would silently hide this
  /// edit, so failures here deliberately propagate rather than being swallowed.
  /// Patching costs 1 read + 1 write instead of rebuilding from scratch.
  /// [removeCode] is the course *code*, not the document id. It used to be the
  /// doc id, compared against a locally re-derived `[^a-zA-Z0-9] -> _` form —
  /// which disagrees with `courseCodeToDocId` (spaces only) for any code
  /// containing a hyphen. `BITS F101-2` and `BITS K101-2` are real Hyderabad
  /// courses, so deleting either left it in the bundle and therefore still
  /// visible everywhere in the app.
  Future<void> _syncCatalogBundle(
    String campusId, {
    Map<String, dynamic>? upsert,
    String? removeCode,
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

    if (removeCode != null) {
      entries.removeWhere((e) => e['course_code'] == removeCode);
    }

    if (upsert != null) {
      final code = upsert['course_code'] as String? ?? '';
      if (code.isEmpty) return;
      final index = entries.indexWhere((e) => e['course_code'] == code);
      final entry = <String, dynamic>{
        'course_code': code,
        'title': upsert['title'] ?? '',
        'credits': (upsert['credits'] as num?) ?? 0,
        // Carried over, not rebuilt: the editor above sets units and never
        // touches hours, so composing the entry from the upsert alone would
        // silently drop the hours out of the bundle on every catalogue edit.
        'credit_hours': (upsert['credit_hours'] as num?) ??
            (index >= 0 ? entries[index]['credit_hours'] ?? 0 : 0),
        'type': upsert['type'] ?? 'Normal',
      };
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

  // ── Courses master (the catalogue itself) ──
  //
  // Deliberately separate from the course CRUD above, which is a *timetable*
  // editor that happens to write the master row alongside. These touch
  // courses_master and nothing else:
  //
  //  - fetchCourses joins from the timetable side, so it can only reach the
  //    ~420 courses offered this semester. 2,429 of the 2,852 catalogue rows
  //    have no timetable document and were unreachable.
  //  - saveCourse always writes a timetable document too, so editing a
  //    catalogue-only row through it would invent a course with no sections.

  static const List<String> courseTypes = ['Normal', 'ATC', 'Lab', 'Project'];

  /// The whole catalogue for [campusId], newest state first from the bundle.
  ///
  /// Reads the single bundle document (1 read) rather than scanning ~2,852
  /// documents, and falls back to the scan only when it is missing — the same
  /// order [CoursesMasterService] uses, and safe because every writer
  /// (this service, and the uploader's `_write_catalog_bundle`) keeps the bundle
  /// in step with the collection.
  Future<List<Map<String, dynamic>>> fetchMasterCourses(
    String campusId, {
    String? query,
    bool forceRefresh = false,
  }) async {
    final rows = await _rows('master', campusId, forceRefresh, () async {
      final snap = await _bundleRef(campusId).get();
      final raw = snap.data()?['entriesJson'] as String?;
      final List<Map<String, dynamic>> all;
      if (raw != null && raw.isNotEmpty) {
        all = [
          for (final e in (jsonDecode(raw) as List).cast<Map>())
            {
              ...Map<String, dynamic>.from(e),
              'docId': courseCodeToDocId(e['course_code'] as String? ?? ''),
            }
        ];
      } else {
        final collection = await _masterRef(campusId).get();
        all = [
          for (final doc in collection.docs) {'docId': doc.id, ...doc.data()}
        ];
      }
      all.sort((a, b) => (a['course_code'] as String? ?? '')
          .compareTo(b['course_code'] as String? ?? ''));
      return all;
    });

    if (query == null || query.isEmpty) return _copy(rows);
    final q = query.toLowerCase();
    return _copy(rows.where((row) {
      final code = (row['course_code'] as String? ?? '').toLowerCase();
      final title = (row['title'] as String? ?? '').toLowerCase();
      return code.contains(q) || title.contains(q);
    }));
  }

  /// Writes one catalogue row, and nothing else.
  ///
  /// [campusIds] is every campus to write it to. The catalogue is stored per
  /// campus and has genuinely drifted — 21 rows differ between Hyderabad and
  /// Pilani, some of it deliberate curation (`BITS F101-2` is type `ATC` only on
  /// Hyderabad) and some of it plainly wrong (`BITS U104` carries 2 credits on
  /// Hyderabad and 0 elsewhere) — so which campuses an edit reaches has to be
  /// the caller's decision rather than a guess made here.
  Future<void> saveMasterCourse({
    required List<String> campusIds,
    required String courseCode,
    required String title,
    required double credits,
    /// Contact hours where the booklet publishes no units — a separate number,
    /// never units x 3. Null leaves whatever is stored alone; 0 clears it. A
    /// caller that does not know about hours must not blank them by omission.
    double? creditHours,
    required String type,
  }) async {
    final docId = courseCodeToDocId(courseCode);
    final data = <String, dynamic>{
      'course_code': courseCode,
      'title': title,
      'credits': credits,
      if (creditHours != null) 'credit_hours': creditHours,
      'type': type,
      'updated_at': DateTime.now().toIso8601String(),
    };
    for (final campusId in campusIds) {
      await _masterRef(campusId).doc(docId).set(data, SetOptions(merge: true));
      _invalidate('master', campusId);
      // Also drops the joined timetable view, which embeds title/credits/type.
      _invalidate('courses', campusId);
      await _syncCatalogBundle(campusId, upsert: data);
    }
  }

  /// Removes one catalogue row from each of [campusIds]. Leaves the timetable
  /// document alone — a course can be offered this semester and still be a
  /// catalogue mistake, and removing the offering is the other screen's job.
  Future<void> deleteMasterCourse({
    required List<String> campusIds,
    required String courseCode,
  }) async {
    final docId = courseCodeToDocId(courseCode);
    for (final campusId in campusIds) {
      await _masterRef(campusId).doc(docId).delete();
      _invalidate('master', campusId);
      _invalidate('courses', campusId);
      await _syncCatalogBundle(campusId, removeCode: courseCode);
    }
  }

  /// Where else [courseCode] is referred to, as lines an admin can read.
  ///
  /// Deleting a catalogue row does not delete what points at it: a prerequisite
  /// chain, a minor's course group or a branch's CDC slot keeps the code and
  /// renders it as a bare code with no title. `sync_courses_master` never
  /// deletes a row for exactly this reason, so a manual delete has to show what
  /// it is about to orphan.
  ///
  /// Matches the serialised document rather than each schema's own shape. Four
  /// collections with four nested layouts would each need their own walker, and
  /// a missed nesting level here reads as "no references" — the one wrong answer
  /// this must not give. Word-bounded so `CS F21` cannot match `CS F211`.
  Future<List<String>> findCourseCodeReferences(
    String campusId,
    String courseCode,
  ) async {
    final docId = courseCodeToDocId(courseCode);
    final pattern = RegExp(
        r'\b('
        '${RegExp.escape(courseCode)}|${RegExp.escape(docId)}'
        r')\b',
        caseSensitive: false);
    bool mentions(Map<String, dynamic>? data) =>
        data != null && pattern.hasMatch(jsonEncode(data));

    final references = <String>[];

    final timetable = await _timetableRef(campusId).doc(docId).get();
    if (timetable.exists) {
      references.add('Offered in this semester\'s timetable');
    }

    final prereqs = await _db
        .collection(FirestoreCollections.reference)
        .doc(FirestoreCollections.prerequisites)
        .collection(FirestoreCollections.courses)
        .get();
    final prereqHits = [
      for (final doc in prereqs.docs)
        if (doc.id == docId || mentions(doc.data())) docIdToCourseCode(doc.id)
    ];
    if (prereqHits.isNotEmpty) {
      references.add('Prerequisites: ${_sample(prereqHits)}');
    }

    final minors = await _db.collection(FirestoreCollections.minors).get();
    final minorHits = [
      for (final doc in minors.docs)
        if (mentions(doc.data()))
          (doc.data()['name'] as String? ?? doc.id)
    ];
    if (minorHits.isNotEmpty) {
      references.add('Minor programmes: ${_sample(minorHits)}');
    }

    final branches = await _db
        .collection(FirestoreCollections.reference)
        .doc(FirestoreCollections.branches)
        .collection(FirestoreCollections.data)
        .get();
    final branchHits = [
      for (final doc in branches.docs)
        if (!doc.id.startsWith('_') && mentions(doc.data())) doc.id
    ];
    if (branchHits.isNotEmpty) {
      references.add('Branch CDC plans: ${_sample(branchHits)}');
    }

    return references;
  }

  static String _sample(List<String> items) {
    const shown = 6;
    if (items.length <= shown) return items.join(', ');
    return '${items.take(shown).join(', ')} (+${items.length - shown} more)';
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
