import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../constants/app_constants.dart';
import 'local_cache_service.dart';

class AcadDrivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  Future<List<Map<String, dynamic>>> fetchAllCoursesData() async {
    if (_allCoursesCache != null) return _allCoursesCache!;

    final cached = await _localCache.read(_cacheKey);
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
    } catch (_) {}

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

  void invalidateCoursesCache() {
    _allCoursesCache = null;
    _localCache.invalidate(_cacheKey);
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
        results.add({'id': doc.id, ...doc.data()});
      }
    }
    return results;
  }

  Future<void> submitDriveLink(Map<String, dynamic> data) {
    return _submissionsRef.add(data);
  }
}
