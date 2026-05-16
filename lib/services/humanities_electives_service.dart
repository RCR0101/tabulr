import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import '../utils/elective_clash_utils.dart';

class HumanitiesElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all humanities electives without clash checking
  Future<List<Course>> getAllHumanitiesElectives(List<Course> availableCourses) async {
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

      // Filter to only HUEL courses that are available in current semester timetable
      final allHuelCourses = availableCourses
          .where((course) => huelCourseCodes.contains(course.courseCode))
          .toList();

      print('Found ${allHuelCourses.length} available HUEL courses without clash filtering');
      return allHuelCourses;

    } catch (e) {
      print('Error in getAllHumanitiesElectives: $e');
      rethrow;
    }
  }

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
      final coreCourseCodes = await ElectiveClashDetector.getCoreCourseCodes(
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
        if (ElectiveClashDetector.doesCourseClashWithCore(course, coreCourseCodes, availableCourses)) {
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

}