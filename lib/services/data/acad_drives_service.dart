import 'dart:convert';
import '../ui/secure_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../../constants/app_constants.dart';
import 'admin_audit_logger.dart';
import 'auth_service.dart';
import 'local_cache_service.dart';

class AcadDrivesService {
  /// Test seam: substitute an in-memory Firestore. Never set from app code.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTest;

  FirebaseFirestore get _firestore => firestoreForTest ?? FirebaseFirestore.instance;

  /// Test seam: the signed-in admin's email. Never set from app code.
  @visibleForTesting
  static String? Function()? reviewerForTest;

  String? get _reviewer => reviewerForTest != null ? reviewerForTest!() : AuthService().userEmail;
  final LocalCacheService _localCache = LocalCacheService();

  static const _cacheKey = 'acad_drives_index';
  List<Map<String, dynamic>>? _allCoursesCache;

  CollectionReference<Map<String, dynamic>> get _indexRef =>
      _firestore.collection(FirestoreCollections.acadDrivesIndex);

  CollectionReference<Map<String, dynamic>> get _filesRef =>
      _firestore.collection(FirestoreCollections.acadDrivesFiles);

  CollectionReference<Map<String, dynamic>> get _submissionsRef =>
      _firestore.collection(FirestoreCollections.acadDrivesSubmissions);

  Future<int> getCourseCount() async {
    final cached = await fetchAllCoursesData();
    if (cached.isNotEmpty) return cached.length;
    final snapshot = await _indexRef.count().get();
    return snapshot.count ?? 0;
  }

  Query<Map<String, dynamic>> buildCourseQuery(String sortField, {bool descending = false, String? secondarySort, bool secondaryDescending = false}) {
    final query = _indexRef.orderBy(sortField, descending: descending);
    if (secondarySort != null) {
      return query.orderBy(secondarySort, descending: secondaryDescending);
    }
    return query;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchCourses(
    Query<Map<String, dynamic>> query, {
    int limit = 40,
    DocumentSnapshot? startAfter,
  }) {
    var q = query.limit(limit);
    if (startAfter != null) {
      q = query.startAfterDocument(startAfter).limit(limit);
    }
    return q.get();
  }

  /// How long the on-disk course index may be served without refetching.
  ///
  /// Deliberately far below LocalCacheService's 72h default. Every other
  /// catalogue service checks a Firestore metadata document for staleness, but
  /// this index comes from R2 over the CDN precisely so it costs no Firestore
  /// reads — polling a metadata document would put that cost straight back.
  /// A short TTL is the cheaper equivalent: the thing it refetches is one
  /// cached CDN GET, so a stale window of days bought almost nothing and hid
  /// newly synced drives from students for up to three of them.
  static const _indexCacheHours = 6;

  Future<List<Map<String, dynamic>>> fetchAllCoursesData() async {
    if (_allCoursesCache != null) return _allCoursesCache!;

    final cached =
        await _localCache.read(_cacheKey, maxAgeHours: _indexCacheHours);
    if (cached != null) {
      _allCoursesCache = cached;
      return cached;
    }

    // Try R2 static JSON first (zero Firestore reads)
    try {
      final response = await http
          .get(Uri.parse(AppUrls.acadDrivesIndexUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final courses = (body['courses'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _allCoursesCache = courses;
        await _localCache.write(_cacheKey, courses);
        return courses;
      }
    } catch (e) {
      SecureLogger.warning('ACAD_DRIVES_SVC', 'Index fetch failed; falling back to Firestore', {'error': e.toString()});
    }

    // Fallback to Firestore
    final snapshot = await _indexRef.get();
    final data = snapshot.docs.map((doc) {
      final m = Map<String, dynamic>.from(doc.data());
      m['_docId'] = doc.id;
      return m;
    }).toList();

    _allCoursesCache = data;
    await _localCache.write(_cacheKey, data);
    return data;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchAllCourses() {
    return _indexRef.get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchCourseFiles(
    String courseCode, {
    int limit = 500,
    DocumentSnapshot? startAfter,
  }) {
    var query = _filesRef
        .where('course_codes', arrayContains: courseCode)
        .orderBy('uploadedAt', descending: true);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    return query.limit(limit).get();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchCoursesByCodes(Set<String> codes) async {
    if (codes.isEmpty) return [];
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final codeList = codes.toList();
    for (var i = 0; i < codeList.length; i += 30) {
      final batch = codeList.sublist(i, i + 30 > codeList.length ? codeList.length : i + 30);
      final snapshot = await _indexRef.where('code', whereIn: batch).get();
      results.addAll(snapshot.docs);
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> fetchFilesByIds(Set<String> fileIds) async {
    if (fileIds.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    final idList = fileIds.toList();
    for (var i = 0; i < idList.length; i += 30) {
      final batch = idList.sublist(i, i + 30 > idList.length ? idList.length : i + 30);
      final snapshot = await _filesRef.where(FieldPath.documentId, whereIn: batch).get();
      for (final doc in snapshot.docs) {
        if (doc.data()['hidden'] == true) continue; // hidden after a report
        results.add({'id': doc.id, ...doc.data()});
      }
    }
    return results;
  }

  Future<void> submitDriveLink(Map<String, dynamic> data) {
    return _submissionsRef.add(data);
  }

  /// Unreviewed submissions, oldest first so the queue drains in order.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> pendingSubmissions() {
    return _submissionsRef.where('status', isEqualTo: 'pending').snapshots().map((s) {
      final docs = s.docs.toList();
      int at(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
          (d.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      docs.sort((a, b) => at(a).compareTo(at(b)));
      return docs;
    });
  }

  /// Adds the drive to the crawler's registry (`acad_drives_sources`) and
  /// closes the submission in one batch. [name] becomes the drive's folder in
  /// R2 and its identity in every file doc, so it must not collide.
  /// Returns false, writing nothing, if a drive with that name already exists.
  Future<bool> approveSubmission(
    QueryDocumentSnapshot<Map<String, dynamic>> submission, {
    required String name,
  }) async {
    final sourceRef = _firestore
        .collection(FirestoreCollections.acadDrivesSources)
        .doc(name.replaceAll('/', '-').trim());
    if ((await sourceRef.get()).exists) return false;

    final data = submission.data();
    final reviewer = _reviewer;
    final batch = _firestore.batch()
      ..set(sourceRef, {
        'name': name.trim(),
        'driveLink': data['driveLink'],
        'contributor': data['contributorName'],
        if (data['courseCode'] != null) 'courseCode': data['courseCode'],
        // What the student said the drive holds; the crawler uses it for
        // files whose names and folders don't say (classify.js).
        if (data['resourceType'] != null) 'resourceType': data['resourceType'],
        'submissionId': submission.id,
        'addedBy': reviewer,
        'addedAt': FieldValue.serverTimestamp(),
      })
      ..update(submission.reference, {
        'status': 'approved',
        'reviewedBy': reviewer,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
    AdminAuditLogger().success('acad_drive_approve', name, {'link': data['driveLink']});
    return true;
  }

  /// Starts the Acad Drives sync now (the GitHub Action) rather than at
  /// Monday's run. Returns null when it started, else why not.
  Future<String?> startSync() async {
    try {
      final r = await FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion)
          .httpsCallable('startAcadDrivesSync')
          .call();
      final data = (r.data as Map?) ?? const {};
      return data['started'] == true ? null : '${data['reason'] ?? 'It syncs on Monday.'}';
    } catch (e) {
      SecureLogger.warning('ACAD_DRIVES_SVC', 'Could not start the sync', {'error': e.toString()});
      return 'Could not start the sync now; it runs on Monday.';
    }
  }

  /// Every drive the crawler syncs, with the outcome of its last sync
  /// (`lastSync`, written by scripts/acad-drives after each run).
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> sources() {
    return _firestore
        .collection(FirestoreCollections.acadDrivesSources)
        .snapshots()
        .map((s) => s.docs);
  }

  /// Takes a drive out of the sync without deleting what it already synced.
  Future<void> setSourceDisabled(DocumentReference<Map<String, dynamic>> ref, bool disabled) async {
    await ref.update({'disabled': disabled});
    AdminAuditLogger().success(disabled ? 'acad_drive_disable' : 'acad_drive_enable', ref.id);
  }

  /// [note] is shown to the student in "My submissions".
  Future<void> rejectSubmission(DocumentReference<Map<String, dynamic>> ref, {String? note}) async {
    await ref.update({
      'status': 'rejected',
      'reviewedBy': _reviewer,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (note != null && note.trim().isNotEmpty) 'reviewNote': note.trim(),
    });
    AdminAuditLogger().success('acad_drive_reject', ref.id);
  }

  // ── Students: their own submissions ──

  /// What [email] has submitted, newest first. The rules let a student read
  /// only their own, so the query must filter on submittedBy.
  Stream<List<MySubmission>> mySubmissions(String email) {
    return _submissionsRef.where('submittedBy', isEqualTo: email).snapshots().map((s) {
      final list = s.docs.map((d) => MySubmission.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => (b.submittedAt ?? DateTime(3000)).compareTo(a.submittedAt ?? DateTime(3000)));
      return list;
    });
  }

  // ── Students: reporting a file ──

  Future<void> reportFile(
    Map<String, dynamic> file, {
    required String reporterEmail,
    required AcadFileProblem problem,
    String? suggestedCourse,
    String? suggestedType,
    String? note,
  }) {
    final codes = (file['course_codes'] as List?) ?? const [];
    return _firestore.collection(FirestoreCollections.acadDrivesReports).add({
      'fileId': file['id'],
      'fileName': '${file['name'] ?? ''}',
      'driveName': '${file['driveName'] ?? ''}',
      'currentCourse': codes.isEmpty ? '' : '${codes.first}',
      'currentType': '${file['resource_type'] ?? 'other'}',
      'problem': problem.key,
      if (suggestedCourse != null) 'suggestedCourse': suggestedCourse,
      if (suggestedType != null) 'suggestedType': suggestedType,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'reportedBy': reporterEmail,
      'status': 'open',
      'reportedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Students: asking for resources ──

  /// Document id for one student's request: asking twice for the same course
  /// and type is the same document, which the rules refuse to overwrite.
  static String requestId(String course, String type, String userDocId) =>
      '${course.trim().replaceAll(RegExp(r'\s+'), '_')}__${type}__$userDocId';

  /// Returns false when this student has already asked for this.
  Future<bool> requestResources({
    required String course,
    required String type,
    required String email,
    required String userDocId,
    String? note,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.acadDrivesRequests)
          .doc(requestId(course, type, userDocId))
          .set({
        'course': course,
        'type': type,
        'requestedBy': email,
        'requestedAt': FieldValue.serverTimestamp(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  // ── Admins: reports, requests, fixes ──

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> openReports() {
    return _firestore
        .collection(FirestoreCollections.acadDrivesReports)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((s) => s.docs.toList()
          ..sort((a, b) => ((a.data()['reportedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
              .compareTo((b.data()['reportedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)));
  }

  /// Applies an admin's fix to the reported file and closes the report, in
  /// one batch. [course] / [type] re-file it (and stop the crawler undoing
  /// that); [hide] takes it out of Acad Drives. Course counts on the course
  /// list catch up at the next sync's index rebuild.
  Future<void> resolveReport(
    QueryDocumentSnapshot<Map<String, dynamic>> report, {
    String? course,
    String? type,
    bool hide = false,
  }) async {
    final fileId = report.data()['fileId'] as String;
    final fileRef = _filesRef.doc(fileId);
    final changes = <String, dynamic>{
      if (course != null) ...{'course_codes': [course], 'manual_course': true},
      if (type != null) ...{
        'resource_type': type,
        'manual_type': true,
        // Exam and year only make sense on papers and solutions.
        if (type != 'pyq' && type != 'solutions') ...{
          'exam': FieldValue.delete(),
          'year': FieldValue.delete(),
        },
      },
      if (hide) 'hidden': true,
    };
    final resolution = [
      if (course != null) 'moved to $course',
      if (type != null) 'typed as $type',
      if (hide) 'hidden',
    ].join(', ');
    final batch = _firestore.batch();
    if (changes.isNotEmpty) batch.update(fileRef, changes);
    batch.update(report.reference, {
      'status': changes.isEmpty ? 'dismissed' : 'fixed',
      'reviewedBy': _reviewer,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (resolution.isNotEmpty) 'resolution': resolution,
    });
    await batch.commit();
    AdminAuditLogger().success('acad_drive_report', fileId, {'resolution': resolution});
  }

  /// Every open request, for the coverage view.
  Future<List<Map<String, dynamic>>> fetchRequests() async {
    final snap = await _firestore.collection(FirestoreCollections.acadDrivesRequests).get();
    return [for (final d in snap.docs) {'id': d.id, ...d.data()}];
  }

  /// Clears a course's requests once it is covered.
  Future<void> clearRequests(String course) async {
    final snap = await _firestore
        .collection(FirestoreCollections.acadDrivesRequests)
        .where('course', isEqualTo: course)
        .get();
    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}


/// What a student can report about a file.
enum AcadFileProblem {
  wrongCourse('wrong_course', 'Filed under the wrong course'),
  wrongType('wrong_type', 'Wrong type (e.g. notes shown as a paper)'),
  broken('broken', "Doesn't open, or is the wrong file"),
  notAcademic('not_academic', 'Not academic material');

  const AcadFileProblem(this.key, this.label);
  final String key;
  final String label;

  static AcadFileProblem? fromKey(String? key) =>
      values.where((p) => p.key == key).firstOrNull;
}

/// One of a student's own drive submissions, and where it has got to.
class MySubmission {
  MySubmission({
    required this.id,
    required this.title,
    required this.driveLink,
    required this.status,
    this.submittedAt,
    this.reviewNote,
    this.syncedAt,
    this.syncedFiles,
    this.syncProblem,
  });

  factory MySubmission.fromMap(String id, Map<String, dynamic> d) {
    final sync = d['syncStatus'] as Map?;
    return MySubmission(
      id: id,
      title: '${d['title'] ?? ''}',
      driveLink: '${d['driveLink'] ?? ''}',
      status: '${d['status'] ?? 'pending'}',
      submittedAt: (d['submittedAt'] as Timestamp?)?.toDate(),
      reviewNote: d['reviewNote'] as String?,
      syncedAt: (sync?['at'] as Timestamp?)?.toDate(),
      syncedFiles: (sync?['files'] as num?)?.toInt(),
      syncProblem: sync?['problem'] as String?,
    );
  }

  final String id;
  final String title;
  final String driveLink;
  final String status;
  final DateTime? submittedAt;
  final String? reviewNote;
  final DateTime? syncedAt;
  final int? syncedFiles;
  final String? syncProblem;

  MySubmissionStage get stage {
    if (status == 'rejected') return MySubmissionStage.rejected;
    if (status != 'approved') return MySubmissionStage.waiting;
    if (syncedAt == null) return MySubmissionStage.approved;
    return syncProblem == null ? MySubmissionStage.live : MySubmissionStage.problem;
  }
}

enum MySubmissionStage { waiting, approved, live, problem, rejected }
