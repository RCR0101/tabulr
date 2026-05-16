import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'secure_logger.dart';
import '../utils/datetime_utils.dart';

class CourseGuideService {
  static final CourseGuideService _instance = CourseGuideService._internal();
  factory CourseGuideService() => _instance;
  CourseGuideService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'course_guide';

  Future<List<CourseGuideSemester>> getAllSemesters() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionName)
          .where(FieldPath.documentId, isNotEqualTo: '_metadata')
          .get();

      final semesters = <CourseGuideSemester>[];
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final semester = CourseGuideSemester.fromFirestore(doc.id, data);
          semesters.add(semester);
        } catch (e) {
          SecureLogger.warning('COURSE_GUIDE', 'Error parsing semester ${doc.id}: $e');
        }
      }

      // Sort semesters by ID
      semesters.sort((a, b) => a.semesterId.compareTo(b.semesterId));

      return semesters;
    } catch (e) {
      SecureLogger.error('COURSE_GUIDE', 'Error loading course guide', e);
      return [];
    }
  }

  Future<CourseGuideMetadata?> getMetadata() async {
    try {
      final doc = await _firestore
          .collection(_collectionName)
          .doc('_metadata')
          .get();

      if (!doc.exists) {
        SecureLogger.warning('COURSE_GUIDE', 'Course guide metadata not found');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        SecureLogger.warning('COURSE_GUIDE', 'Course guide metadata document is empty');
        return null;
      }

      return CourseGuideMetadata.fromFirestore(data);
    } catch (e) {
      SecureLogger.error('COURSE_GUIDE', 'Error loading course guide metadata', e);
      return null;
    }
  }

  Stream<List<CourseGuideSemester>> watchSemesters() {
    return _firestore
        .collection(_collectionName)
        .where(FieldPath.documentId, isNotEqualTo: '_metadata')
        .snapshots()
        .map((snapshot) {
          final semesters = <CourseGuideSemester>[];
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              final semester = CourseGuideSemester.fromFirestore(doc.id, data);
              semesters.add(semester);
            } catch (e) {
              SecureLogger.warning('COURSE_GUIDE', 'Error parsing semester ${doc.id}: $e');
            }
          }
          semesters.sort((a, b) => a.semesterId.compareTo(b.semesterId));
          return semesters;
        });
  }
}

class CourseGuideSemester {
  final String semesterId;
  final String name;
  final DateTime lastUpdated;
  final List<CourseGuideGroup> groups;

  CourseGuideSemester({
    required this.semesterId,
    required this.name,
    required this.lastUpdated,
    required this.groups,
  });

  factory CourseGuideSemester.fromFirestore(String id, Map<String, dynamic> data) {
    final groupsData = data['groups'] as Map<String, dynamic>? ?? {};
    final groups = <CourseGuideGroup>[];

    for (final entry in groupsData.entries) {
      try {
        final group = CourseGuideGroup.fromFirestore(entry.key, entry.value);
        groups.add(group);
      } catch (e) {
        SecureLogger.warning('COURSE_GUIDE', 'Error parsing group ${entry.key}: $e');
      }
    }

    return CourseGuideSemester(
      semesterId: id,
      name: data['name'] ?? id,
      lastUpdated: parseDateTime(data['lastUpdated']),
      groups: groups,
    );
  }

}

class CourseGuideGroup {
  final String groupId;
  final List<String> branches;
  final List<CourseGuideEntry> courses;

  CourseGuideGroup({
    required this.groupId,
    required this.branches,
    required this.courses,
  });

  factory CourseGuideGroup.fromFirestore(String id, Map<String, dynamic> data) {
    final branchesData = data['branches'] as List<dynamic>? ?? [];
    final branches = branchesData.map((b) => b.toString()).toList();

    final coursesData = data['courses'] as List<dynamic>? ?? [];
    final courses = <CourseGuideEntry>[];

    for (final courseData in coursesData) {
      if (courseData is Map<String, dynamic>) {
        try {
          final course = CourseGuideEntry.fromFirestore(courseData);
          courses.add(course);
        } catch (e) {
          SecureLogger.warning('COURSE_GUIDE', 'Error parsing course: $e');
        }
      }
    }

    return CourseGuideGroup(
      groupId: id,
      branches: branches,
      courses: courses,
    );
  }

  String get displayName {
    return branches.join(', ');
  }
}

class CourseGuideEntry {
  final String code;
  final String name;
  final int credits;
  final String type;

  CourseGuideEntry({
    required this.code,
    required this.name,
    required this.credits,
    required this.type,
  });

  factory CourseGuideEntry.fromFirestore(Map<String, dynamic> data) {
    return CourseGuideEntry(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      credits: (data['credits'] as num?)?.toInt() ?? 0,
      type: data['type'] ?? 'Lecture',
    );
  }
}

class CourseGuideMetadata {
  final int totalSemesters;
  final List<String> availableSemesters;
  final DateTime lastUpdated;
  final String uploadedBy;
  final String version;

  CourseGuideMetadata({
    required this.totalSemesters,
    required this.availableSemesters,
    required this.lastUpdated,
    required this.uploadedBy,
    required this.version,
  });

  factory CourseGuideMetadata.fromFirestore(Map<String, dynamic> data) {
    final availableList = data['availableSemesters'] as List<dynamic>? ?? [];
    
    return CourseGuideMetadata(
      totalSemesters: (data['totalSemesters'] as num?)?.toInt() ?? 0,
      availableSemesters: availableList.map((s) => s.toString()).toList(),
      lastUpdated: parseDateTime(data['lastUpdated']),
      uploadedBy: data['uploadedBy'] ?? 'Unknown',
      version: data['version'] ?? '1.0.0',
    );
  }

}