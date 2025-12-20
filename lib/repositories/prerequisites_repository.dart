import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/prerequisite.dart';

class PrerequisitesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Search for courses by course code or name
  Future<List<CoursePrerequisites>> searchCourses(String query) async {
    if (query.isEmpty) {
      return [];
    }

    final lowercaseQuery = query.toLowerCase();

    try {
      // Search by course code
      final codeQuery = await _firestore
          .collection('prerequisites')
          .where('course_code_lower', isGreaterThanOrEqualTo: lowercaseQuery)
          .where('course_code_lower', isLessThan: '${lowercaseQuery}z')
          .limit(20)
          .get();

      // Search by name
      final nameQuery = await _firestore
          .collection('prerequisites')
          .where('name_lower', isGreaterThanOrEqualTo: lowercaseQuery)
          .where('name_lower', isLessThan: '${lowercaseQuery}z')
          .limit(20)
          .get();

      // Combine results and remove duplicates
      final Set<String> seenIds = {};
      final List<CoursePrerequisites> results = [];

      for (var doc in [...codeQuery.docs, ...nameQuery.docs]) {
        if (!seenIds.contains(doc.id)) {
          seenIds.add(doc.id);
          results.add(CoursePrerequisites.fromMap(doc.data()));
        }
      }

      // Sort by course code
      results.sort((a, b) => a.courseCode.compareTo(b.courseCode));

      return results;
    } catch (e) {
      print('Error searching courses: $e');
      return [];
    }
  }

  /// Get prerequisites for a specific course
  Future<CoursePrerequisites?> getCoursePrerequisites(String courseName) async {
    try {
      final docId = courseName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final doc = await _firestore
          .collection('prerequisites')
          .doc(docId)
          .get();

      if (doc.exists) {
        return CoursePrerequisites.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting course prerequisites: $e');
      return null;
    }
  }

  /// Get all courses with prerequisites
  Future<List<CoursePrerequisites>> getCoursesWithPrerequisites() async {
    try {
      final snapshot = await _firestore
          .collection('prerequisites')
          .where('has_prerequisites', isEqualTo: true)
          .orderBy('course_code_lower')
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting courses with prerequisites: $e');
      return [];
    }
  }

  /// Get all courses (for initial display when no search)
  Future<List<CoursePrerequisites>> getAllCourses({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection('prerequisites')
          .orderBy('course_code_lower')
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting all courses: $e');
      return [];
    }
  }
}
