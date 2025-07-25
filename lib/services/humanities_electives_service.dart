import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import 'campus_service.dart';

class HumanitiesElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mapping from branch codes to full branch names
  static const Map<String, String> _branchCodeToName = {
    'A1': 'Chemical Engineering',
    'A2': 'Civil Engineering', 
    'A3': 'Electrical and Electronics Engineering',
    'A4': 'Mechanical Engineering',
    'A7': 'Computer Science',
    'A8': 'Electronics and Instrumentation',
    'AA': 'Electronics and Communication Engineering',
    'AB': 'Manufacturing',
    'B1': 'Chemistry',
    'B2': 'Economics',
    'B3': 'Electrical and Electronics',
    'B4': 'Mechanical',
    'B5': 'Civil',
    'C1': 'Economics and Finance',
    'C2': 'General Studies',
    'C3': 'Information Systems',
    'C4': 'Manufacturing Engineering',
    'C5': 'Pharmacy',
    'C6': 'Biotechnology',
    'C7': 'Computer Science and Information Systems',
    'C8': 'Electronics and Communication',
    'D1': 'Mathematics',
    'D2': 'Physics',
    'D3': 'Chemistry',
    'D4': 'Biology',
    'D5': 'Economics'
  };

  // Get filtered humanities electives based on branch and semester
  Future<List<Course>> getFilteredHumanitiesElectives(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
    List<Course> availableCourses,
  ) async {
    try {
      // Get HUEL courses from Firebase
      final huelSnapshot = await _firestore.collection('huel_guide').get();
      
      if (huelSnapshot.docs.isEmpty) {
        print('No HUEL courses found in database');
        return [];
      }

      // Extract HUEL course codes (excluding metadata document)
      final huelCourseCodes = <String>{};
      for (final doc in huelSnapshot.docs) {
        if (doc.id == '_metadata') continue;
        
        final data = doc.data();
        final courseCode = data['course_code'] as String?;
        if (courseCode != null) {
          huelCourseCodes.add(courseCode);
        }
      }

      print('Found ${huelCourseCodes.length} HUEL courses in database');

      // Get core courses for the specified branches and semesters
      final coreCourseCodes = await _getCoreCourseCodes(
        primarySemester,
        primaryBranch,
        secondarySemester,
        secondaryBranch,
      );

      print('Found ${coreCourseCodes.length} core courses for filtering');

      // Filter HUEL courses that:
      // 1. Are available in current semester timetable
      // 2. Don't clash with core courses
      final filteredHuelCourses = <Course>[];

      for (final course in availableCourses) {
        // Check if this course is a HUEL course
        if (!huelCourseCodes.contains(course.courseCode)) {
          continue;
        }

        // Check if this HUEL course clashes with any core course
        if (_doesCourseClashWithCore(course, coreCourseCodes, availableCourses)) {
          print('HUEL course ${course.courseCode} clashes with core courses, excluding');
          continue;
        }

        filteredHuelCourses.add(course);
      }

      print('Filtered to ${filteredHuelCourses.length} non-clashing HUEL courses');
      return filteredHuelCourses;

    } catch (e) {
      print('Error in getFilteredHumanitiesElectives: $e');
      rethrow;
    }
  }

  // Get core course codes for specified branches and semesters
  Future<Set<String>> _getCoreCourseCodes(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
  ) async {
    final coreCourseCodes = <String>{};

    // Get primary branch/semester courses
    await _addCoreCoursesForBranchSemester(
      coreCourseCodes,
      primarySemester,
      primaryBranch,
    );

    // Get secondary branch/semester courses if specified
    if (secondarySemester != null && secondaryBranch != null) {
      await _addCoreCoursesForBranchSemester(
        coreCourseCodes,
        secondarySemester,
        secondaryBranch,
      );
    }

    return coreCourseCodes;
  }

  // Add core courses for a specific branch and semester
  Future<void> _addCoreCoursesForBranchSemester(
    Set<String> coreCourseCodes,
    String semester,
    String branch,
  ) async {
    try {
      // Convert semester format from "2-1" to "semester_2_1"
      final semesterDocId = 'semester_${semester.replaceAll('-', '_')}';
      
      final courseGuideDoc = await _firestore
          .collection('course_guide')
          .doc(semesterDocId)
          .get();

      if (!courseGuideDoc.exists) {
        print('Course guide not found for semester: $semesterDocId');
        return;
      }

      final data = courseGuideDoc.data();
      if (data == null || !data.containsKey('groups')) {
        print('No groups found in course guide for semester: $semesterDocId');
        return;
      }

      final groups = data['groups'] as Map<String, dynamic>;

      // Convert branch code to branch name
      final branchName = _branchCodeToName[branch];
      if (branchName == null) {
        print('Unknown branch code: $branch');
        return;
      }

      // Look for group with matching branch name
      for (final entry in groups.entries) {
        final groupData = entry.value as Map<String, dynamic>;
        final branches = List<String>.from(groupData['branches'] ?? []);
        
        if (branches.contains(branchName)) {
          // Add all courses from this group
          final courses = List<dynamic>.from(groupData['courses'] ?? []);
          for (final courseData in courses) {
            if (courseData is Map<String, dynamic>) {
              final courseCode = courseData['code'] as String?;
              if (courseCode != null) {
                coreCourseCodes.add(courseCode);
              }
            }
          }
          print('Found group for $branch ($branchName) with ${courses.length} courses');
        }
      }

      print('Added ${coreCourseCodes.length} total core courses for $branch $semester');
    } catch (e) {
      print('Error getting core courses for $branch $semester: $e');
    }
  }

  // Check if a HUEL course clashes with any core course
  bool _doesCourseClashWithCore(
    Course huelCourse,
    Set<String> coreCourseCodes,
    List<Course> availableCourses,
  ) {
    // Find core courses in the available courses list
    final coreCourses = availableCourses
        .where((course) => coreCourseCodes.contains(course.courseCode))
        .toList();

    // Check if HUEL course sections clash with any core course sections
    for (final huelSection in huelCourse.sections) {
      for (final coreCoreCourse in coreCourses) {
        for (final coreSection in coreCoreCourse.sections) {
          if (_doSectionsClash(huelSection, coreSection)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  // Check if two sections have time clashes
  bool _doSectionsClash(Section section1, Section section2) {
    for (final schedule1 in section1.schedule) {
      for (final schedule2 in section2.schedule) {
        // Check if they share any common days
        final commonDays = schedule1.days.toSet().intersection(schedule2.days.toSet());
        if (commonDays.isNotEmpty) {
          // Check if they share any common hours
          final commonHours = schedule1.hours.toSet().intersection(schedule2.hours.toSet());
          if (commonHours.isNotEmpty) {
            return true; // Clash detected
          }
        }
      }
    }
    return false; // No clash
  }
}