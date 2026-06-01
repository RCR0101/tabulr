import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';

class AcadDrivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _indexRef =>
      _firestore.collection(FirestoreCollections.acadDrivesIndex);

  CollectionReference<Map<String, dynamic>> get _filesRef =>
      _firestore.collection(FirestoreCollections.acadDrivesFiles);

  CollectionReference<Map<String, dynamic>> get _submissionsRef =>
      _firestore.collection(FirestoreCollections.acadDrivesSubmissions);

  Future<int> getCourseCount() async {
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

  Future<QuerySnapshot<Map<String, dynamic>>> fetchAllCourses() {
    return _indexRef.get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchCourseFiles(
    String courseCode, {
    int limit = 500,
  }) {
    return _filesRef
        .where('course_codes', arrayContains: courseCode)
        .orderBy('uploadedAt', descending: true)
        .limit(limit)
        .get();
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

  Future<void> submitDriveLink(Map<String, dynamic> data) {
    return _submissionsRef.add(data);
  }
}
