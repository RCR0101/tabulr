import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/prerequisite.dart';
import '../services/data/courses_master_service.dart';

class PrerequisitesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _prereqsRef =>
      _firestore.collection('reference').doc('prerequisites').collection('courses');

  List<CoursePrerequisites>? _cache;

  Future<List<CoursePrerequisites>> _loadAll() async {
    if (_cache != null) return _cache!;
    final snapshot = await _prereqsRef.get();
    _cache = snapshot.docs
        .map((doc) => CoursePrerequisites.fromMap(doc.data()))
        .toList();
    return _cache!;
  }

  void clearCache() {
    _cache = null;
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
