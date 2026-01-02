import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/prerequisite.dart';

class PrerequisitesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<List<CoursePrerequisites>> searchCourses(String query) async {
    if (query.isEmpty) {
      return [];
    }

    final lowercaseQuery = query.toLowerCase().trim();
    final Set<String> seenIds = {};
    final List<CoursePrerequisites> results = [];

    try {
      // 1. Exact course code match (highest priority)
      final exactCodeQuery = await _firestore
          .collection('prerequisites')
          .where('course_code_lower', isEqualTo: lowercaseQuery)
          .limit(10)
          .get();

      for (var doc in exactCodeQuery.docs) {
        if (!seenIds.contains(doc.id)) {
          seenIds.add(doc.id);
          results.add(CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>));
        }
      }

      // 2. Course code prefix match
      if (results.length < 15) {
        final codeQuery = await _firestore
            .collection('prerequisites')
            .where('course_code_lower', isGreaterThanOrEqualTo: lowercaseQuery)
            .where('course_code_lower', isLessThan: '${lowercaseQuery}z')
            .limit(15)
            .get();

        for (var doc in codeQuery.docs) {
          if (!seenIds.contains(doc.id)) {
            seenIds.add(doc.id);
            results.add(CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>));
          }
        }
      }

      // 3. Full name prefix match
      if (results.length < 15) {
        final nameQuery = await _firestore
            .collection('prerequisites')
            .where('name_lower', isGreaterThanOrEqualTo: lowercaseQuery)
            .where('name_lower', isLessThan: '${lowercaseQuery}z')
            .limit(15)
            .get();

        for (var doc in nameQuery.docs) {
          if (!seenIds.contains(doc.id)) {
            seenIds.add(doc.id);
            results.add(CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>));
          }
        }
      }

      // 4. Search within course titles (handles partial name matches)
      if (results.length < 15 && lowercaseQuery.length >= 3) {
        // Get all courses and filter client-side for partial name matches
        final allCoursesQuery = await _firestore
            .collection('prerequisites')
            .limit(500) // Reasonable limit for client-side filtering
            .get();

        for (var doc in allCoursesQuery.docs) {
          if (seenIds.contains(doc.id)) continue;
          
          final data = doc.data() as Map<String, dynamic>;
          final nameLower = data['name_lower'] as String? ?? '';
          final courseCodeLower = data['course_code_lower'] as String? ?? '';
          
          // Extract course title (everything after course code)
          final courseTitleStart = nameLower.indexOf(' ', courseCodeLower.length);
          if (courseTitleStart > 0) {
            final courseTitle = nameLower.substring(courseTitleStart + 1);
            
            // Check if query matches any word in the title or is contained within title
            if (_matchesCourseTitle(courseTitle, lowercaseQuery)) {
              seenIds.add(doc.id);
              results.add(CoursePrerequisites.fromMap(data));
              
              if (results.length >= 20) break; // Prevent too many results
            }
          }
        }
      }

      // 5. If query looks like a subject code (e.g., "CS", "BIO"), search by subject
      if (results.length < 10 && _isSubjectCode(lowercaseQuery)) {
        final subjectQuery = await _firestore
            .collection('prerequisites')
            .where('course_code_lower', isGreaterThanOrEqualTo: '$lowercaseQuery ')
            .where('course_code_lower', isLessThan: '$lowercaseQuery~')
            .limit(20)
            .get();

        for (var doc in subjectQuery.docs) {
          if (!seenIds.contains(doc.id)) {
            seenIds.add(doc.id);
            results.add(CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>));
          }
        }
      }

      results.sort((a, b) {
        final aCodeLower = a.courseCode.toLowerCase();
        final bCodeLower = b.courseCode.toLowerCase();
        
        // Exact matches first
        final aExact = aCodeLower == lowercaseQuery;
        final bExact = bCodeLower == lowercaseQuery;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        
        // Then by course code prefix match
        final aStartsWith = aCodeLower.startsWith(lowercaseQuery);
        final bStartsWith = bCodeLower.startsWith(lowercaseQuery);
        if (aStartsWith && !bStartsWith) return -1;
        if (!aStartsWith && bStartsWith) return 1;
        
        return a.courseCode.compareTo(b.courseCode);
      });

      return results.take(25).toList();
    } catch (e) {
      print('Error searching courses: $e');
      return [];
    }
  }

  /// Check if query looks like a subject code (2-4 letters)
  bool _isSubjectCode(String query) {
    return RegExp(r'^[a-z]{2,4}$').hasMatch(query);
  }

  /// Check if query matches course title using word-based and substring matching
  bool _matchesCourseTitle(String courseTitle, String query) {
    // Simple substring match
    if (courseTitle.contains(query)) {
      return true;
    }
    
    // Word-based matching - check if query matches start of any word
    final words = courseTitle.split(' ');
    final queryWords = query.split(' ');
    
    // If query has multiple words, try to match them in sequence
    if (queryWords.length > 1) {
      for (int i = 0; i <= words.length - queryWords.length; i++) {
        bool allMatch = true;
        for (int j = 0; j < queryWords.length; j++) {
          if (!words[i + j].startsWith(queryWords[j])) {
            allMatch = false;
            break;
          }
        }
        if (allMatch) return true;
      }
    } else {
      // Single word query - check if it starts any word in title
      for (final word in words) {
        if (word.startsWith(query)) {
          return true;
        }
      }
    }
    
    return false;
  }

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

  Future<List<CoursePrerequisites>> getCoursesWithPrerequisites() async {
    try {
      final snapshot = await _firestore
          .collection('prerequisites')
          .where('has_prerequisites', isEqualTo: true)
          .orderBy('course_code_lower')
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting courses with prerequisites: $e');
      return [];
    }
  }

  Future<List<CoursePrerequisites>> getAllCourses({int limit = 200}) async {
    try {
      final snapshot = await _firestore
          .collection('prerequisites')
          .orderBy('course_code_lower')
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting all courses: $e');
      return [];
    }
  }

  Future<List<CoursePrerequisites>> getFilteredCourses({
    bool? hasPrerequisites,
    int limit = 100,
  }) async {
    try {
      Query query = _firestore.collection('prerequisites');
      
      if (hasPrerequisites != null) {
        query = query.where('has_prerequisites', isEqualTo: hasPrerequisites);
      }
      
      final snapshot = await query
          .orderBy('course_code_lower')
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting filtered courses: $e');
      return [];
    }
  }

  Future<List<CoursePrerequisites>> getCoursesByDepartment(
    String departmentCode,
    {int limit = 50}
  ) async {
    try {
      final deptLower = departmentCode.toLowerCase();
      final snapshot = await _firestore
          .collection('prerequisites')
          .where('course_code_lower', isGreaterThanOrEqualTo: '$deptLower ')
          .where('course_code_lower', isLessThan: '$deptLower~')
          .orderBy('course_code_lower')
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CoursePrerequisites.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting courses by department: $e');
      return [];
    }
  }
}
