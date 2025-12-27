import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import 'campus_service.dart';

class HumanitiesElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mapping from branch codes to full branch names
  static const Map<String, String> _branchCodeToName = {
    'A1': 'Chemical',
    'A2': 'Civil', 
    'A3': 'Electrical and Electronics',
    'A4': 'Mechanical',
    'A5': 'Pharma',
    'A7': 'Computer Science',
    'A8': 'Electronics and Instrumentation',
    'AA': 'Electronics and Communication',
    'AB': 'Manufacturing',
    'AD': 'Math and Computing',
    'B1': 'MSc Biology',
    'B2': 'MSc Chemistry',
    'B3': 'MSc Economics',
    'B4': 'MSc Mathematics',
    'B5': 'MSc Physics',
  };

  // Get all humanities electives without clash checking
  Future<List<Course>> getAllHumanitiesElectives(List<Course> availableCourses) async {
    try {
      // Get HUEL courses from Firebase
      final huelSnapshot = await _firestore.collection('huel_guide').get();
      
      if (huelSnapshot.docs.isEmpty) {
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


      // Filter to only HUEL courses that are available in current semester timetable
      final allHuelCourses = availableCourses
          .where((course) => huelCourseCodes.contains(course.courseCode))
          .toList();

      return allHuelCourses;

    } catch (e) {
      // Error in getAllHumanitiesElectives: $e
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


      // Get core courses for the specified branches and semesters
      final coreCourseCodes = await _getCoreCourseCodes(
        primarySemester,
        primaryBranch,
        secondarySemester,
        secondaryBranch,
      );


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
          continue;
        }

        filteredHuelCourses.add(course);
      }

      return filteredHuelCourses;

    } catch (e) {
      // Error in getFilteredHumanitiesElectives: $e
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
        return;
      }

      final data = courseGuideDoc.data();
      if (data == null || !data.containsKey('groups')) {
        return;
      }

      final groups = data['groups'] as Map<String, dynamic>;

      // Convert branch code to branch name
      final branchName = _branchCodeToName[branch];
      if (branchName == null) {
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
        }
      }

    } catch (e) {
      // Error getting core courses for $branch $semester: $e
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

    // First check exam clashes
    for (final coreCourse in coreCourses) {
      if (_hasExamClash(huelCourse, coreCourse)) {
        return true;
      }
    }

    // Then check time clashes with section-type awareness
    // Group HUEL sections by type
    final huelLectures = huelCourse.sections.where((s) => s.type == SectionType.L).toList();
    final huelPracticals = huelCourse.sections.where((s) => s.type == SectionType.P).toList();
    final huelTutorials = huelCourse.sections.where((s) => s.type == SectionType.T).toList();

    for (final coreCourse in coreCourses) {
      // Group core course sections by type
      final coreLectures = coreCourse.sections.where((s) => s.type == SectionType.L).toList();
      final corePracticals = coreCourse.sections.where((s) => s.type == SectionType.P).toList();
      final coreTutorials = coreCourse.sections.where((s) => s.type == SectionType.T).toList();

      // Check if ALL sections of same type clash (means no viable option)
      if (_allSectionsClash(huelLectures, coreLectures) ||
          _allSectionsClash(huelPracticals, corePracticals) ||
          _allSectionsClash(huelTutorials, coreTutorials)) {
        return true;
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

  // Check if two courses have exam clashes
  bool _hasExamClash(Course course1, Course course2) {
    // Check MidSem exam clash
    if (course1.midSemExam != null && course2.midSemExam != null) {
      if (_examTimesConflict(course1.midSemExam!, course2.midSemExam!)) {
        return true;
      }
    }
    
    // Check EndSem exam clash
    if (course1.endSemExam != null && course2.endSemExam != null) {
      if (_examTimesConflict(course1.endSemExam!, course2.endSemExam!)) {
        return true;
      }
    }
    
    return false;
  }

  // Check if exam times conflict
  bool _examTimesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    return exam1.date.day == exam2.date.day && 
           exam1.date.month == exam2.date.month && 
           exam1.date.year == exam2.date.year &&
           exam1.timeSlot == exam2.timeSlot;
  }

  // Check if ALL sections of one type clash with ALL sections of another type
  // This means there's no way to pick compatible sections
  bool _allSectionsClash(List<Section> sections1, List<Section> sections2) {
    if (sections1.isEmpty || sections2.isEmpty) {
      return false; // No clash if either has no sections of this type
    }

    // Check if every section in sections1 clashes with every section in sections2
    for (final section1 in sections1) {
      bool hasNonClashingOption = false;
      for (final section2 in sections2) {
        if (!_doSectionsClash(section1, section2)) {
          hasNonClashingOption = true;
          break;
        }
      }
      // If this section1 has at least one non-clashing option in sections2,
      // then not all sections clash
      if (hasNonClashingOption) {
        return false;
      }
    }
    
    // All sections in sections1 clash with all sections in sections2
    return true;
  }
}