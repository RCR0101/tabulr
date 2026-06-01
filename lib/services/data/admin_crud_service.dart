import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';

class AdminCrudService {
  static final AdminCrudService _instance = AdminCrudService._internal();
  factory AdminCrudService() => _instance;
  AdminCrudService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _timetableRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection('timetable');

  CollectionReference<Map<String, dynamic>> _masterRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.coursesMaster);

  CollectionReference<Map<String, dynamic>> _examRef(String campusId) =>
      _db.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.examSeating);

  CollectionReference<Map<String, dynamic>> _profsRef(String campusId) =>
      _db.collection(FirestoreCollections.reference).doc(FirestoreCollections.professors).collection('$campusId-entries');

  // ── Courses ──

  Future<List<Map<String, dynamic>>> fetchCourses(String campusId, {String? query}) async {
    final timetableSnap = await _timetableRef(campusId).get();
    final masterSnap = await _masterRef(campusId).get();
    final masterMap = {for (final d in masterSnap.docs) d.id: d.data()};

    final results = <Map<String, dynamic>>[];
    for (final doc in timetableSnap.docs) {
      final master = masterMap[doc.id];
      final data = {
        'docId': doc.id,
        ...doc.data(),
        'course_code': master?['course_code'] ?? doc.id.replaceAll('_', ' '),
        'title': master?['title'] ?? '',
        'credits': master?['credits'] ?? 0,
        'type': master?['type'] ?? 'Normal',
      };
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        final code = (data['course_code'] as String).toLowerCase();
        final title = (data['title'] as String).toLowerCase();
        if (!code.contains(q) && !title.contains(q)) continue;
      }
      results.add(data);
    }
    results.sort((a, b) =>
        (a['course_code'] as String).compareTo(b['course_code'] as String));
    return results;
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
  }

  Future<void> deleteCourse(String campusId, String docId) async {
    final batch = _db.batch();
    batch.delete(_timetableRef(campusId).doc(docId));
    batch.delete(_masterRef(campusId).doc(docId));
    await batch.commit();
  }

  // ── Exam Seating ──

  Future<List<Map<String, dynamic>>> fetchExamSeating(String campusId, {String? query}) async {
    final snap = await _examRef(campusId).get();
    final results = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = {'docId': doc.id, ...doc.data()};
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!doc.id.toLowerCase().contains(q)) continue;
      }
      results.add(data);
    }
    results.sort((a, b) =>
        (a['docId'] as String).compareTo(b['docId'] as String));
    return results;
  }

  Future<void> saveExamSeating(String campusId, String docId, Map<String, dynamic> data) async {
    await _examRef(campusId).doc(docId).set(data);
  }

  Future<void> deleteExamSeating(String campusId, String docId) async {
    await _examRef(campusId).doc(docId).delete();
  }

  // ── Professors ──

  Future<List<Map<String, dynamic>>> fetchProfessors(String campusId, {String? query}) async {
    final snap = await _profsRef(campusId).get();
    final results = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = {'docId': doc.id, ...doc.data()};
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        final name = (data['name'] as String? ?? '').toLowerCase();
        final chamber = (data['chamber'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !chamber.contains(q)) continue;
      }
      results.add(data);
    }
    results.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return results;
  }

  Future<void> saveProfessor(String campusId, String docId, Map<String, dynamic> data) async {
    await _profsRef(campusId).doc(docId).set(data, SetOptions(merge: true));
  }

  Future<void> deleteProfessor(String campusId, String docId) async {
    await _profsRef(campusId).doc(docId).delete();
  }
}
