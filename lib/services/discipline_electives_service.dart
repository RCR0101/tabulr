import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';

class DisciplineElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mapping from branch codes to full branch names (same as humanities service)
  static const Map<String, String> _branchCodeToName = {
    'A1': 'Chemical Engineering',
    'A2': 'Civil Engineering', 
    'A3': 'Electrical and Electronics Engineering',
    'A4': 'Mechanical Engineering',
    'A5': 'B Pharma',
    'A7': 'Computer Science',
    'A8': 'Electronics and Instrumentation',
    'AA': 'Electronics and Communication Engineering',
    'AB': 'Manufacturing',
    'AD': 'Mathematics And Computing',
    'B1': 'MSc Biological Sciences',
    'B2': 'MSc Chemistry',
    'B3': 'MSc Economics',
    'B4': 'MSc Mathematics',
    'B5': 'MSc Physics',
  };
  
  // Get all available branches
  Future<List<BranchInfo>> getAvailableBranches() async {
    try {
      print('Fetching metadata from Firestore...');
      final metadataDoc = await _firestore
          .collection('discipline_electives')
          .doc('_metadata')
          .get()
          .timeout(Duration(seconds: 10));
      
      print('Metadata doc exists: ${metadataDoc.exists}');
      
      if (!metadataDoc.exists) {
        print('Metadata not found, using fallback data');
        return _getFallbackBranches();
      }
      
      final data = metadataDoc.data()!;
      print('Metadata data keys: ${data.keys.toList()}');
      
      if (data.containsKey('branchCodes')) {
        final branchCodes = data['branchCodes'] as List<dynamic>;
        print('Branch codes count: ${branchCodes.length}');
        
        final branches = branchCodes.map((branch) => BranchInfo(
          name: branch['name'] as String,
          code: branch['code'] as String,
        )).toList();
        
        print('Parsed branches: ${branches.map((b) => b.name).join(', ')}');
        return branches;
      } else {
        print('branchCodes key not found, using fallback');
        return _getFallbackBranches();
      }
    } catch (e) {
      print('Error loading branches: $e');
      print('Using fallback data due to error');
      return _getFallbackBranches();
    }
  }
  
  // Fallback data for development/testing
  List<BranchInfo> _getFallbackBranches() {
    return [
      BranchInfo(name: 'Civil Engineering', code: 'CE'),
      BranchInfo(name: 'Chemical Engineering', code: 'CHE'),
      BranchInfo(name: 'Electronics and Electrical Engineering', code: 'EEE'),
      BranchInfo(name: 'Mechanical Engineering', code: 'ME'),
      BranchInfo(name: 'B Pharma', code: 'PHA'),
      BranchInfo(name: 'Computer Science', code: 'CS'),
      BranchInfo(name: 'Electronics and Instrumentation', code: 'EI'),
      BranchInfo(name: 'MSc. Biological Sciences', code: 'BIO'),
      BranchInfo(name: 'MSc. Chemistry', code: 'CHEM'),
      BranchInfo(name: 'MSc. Economics', code: 'ECON'),
      BranchInfo(name: 'MSc. Mathematics', code: 'MATH'),
      BranchInfo(name: 'MSc. Physics', code: 'PHY'),
    ];
  }
  
  // Get discipline electives for a branch
  Future<List<DisciplineElective>> getDisciplineElectives(String branchName) async {
    try {
      print('Fetching discipline electives for: $branchName');
      
      // Convert branch name to document ID
      final branchId = branchName.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '-');
      
      print('Branch ID: $branchId');
      
      final doc = await _firestore
          .collection('discipline_electives')
          .doc(branchId)
          .get()
          .timeout(Duration(seconds: 10));
      
      print('Document exists: ${doc.exists}');
      
      if (!doc.exists) {
        print('Document not found, returning empty list');
        return [];
      }
      
      final data = doc.data()!;
      print('Document data keys: ${data.keys.toList()}');
      
      if (!data.containsKey('courses')) {
        print('No courses field found, returning empty list');
        return [];
      }
      
      final courses = data['courses'] as List<dynamic>;
      print('Found ${courses.length} courses');
      
      return courses.map((course) => DisciplineElective(
        courseCode: course['course_code'] as String,
        courseName: course['course_name'] as String,
        branchName: branchName,
      )).toList();
    } catch (e) {
      print('Error in getDisciplineElectives: $e');
      // Return empty list instead of throwing
      return [];
    }
  }
  
  // Get filtered discipline electives based on branch selection and available courses
  Future<List<DisciplineElective>> getFilteredDisciplineElectives(
    String primaryBranch,
    String? secondaryBranch,
    List<Course> availableCourses,
  ) async {
    try {
      // Get discipline electives for primary branch
      List<DisciplineElective> electives = await getDisciplineElectives(primaryBranch);
      
      // If secondary branch is selected, get its electives too
      if (secondaryBranch != null && secondaryBranch.isNotEmpty) {
        final secondaryElectives = await getDisciplineElectives(secondaryBranch);
        electives.addAll(secondaryElectives);
      }
      
      // Filter to only include courses that exist in the available courses
      final availableCourseCodes = availableCourses.map((c) => c.courseCode).toSet();
      
      final filteredElectives = electives.where((elective) {
        return availableCourseCodes.contains(elective.courseCode);
      }).toList();
      
      // Remove duplicates (in case both branches have same electives)
      final uniqueElectives = <String, DisciplineElective>{};
      for (final elective in filteredElectives) {
        uniqueElectives[elective.courseCode] = elective;
      }
      
      return uniqueElectives.values.toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));
    } catch (e) {
      throw Exception('Failed to filter discipline electives: $e');
    }
  }
  
  // Get filtered discipline electives with clash detection
  Future<List<DisciplineElective>> getFilteredDisciplineElectivesWithClashDetection(
    String primaryBranch,
    String? secondaryBranch,
    String primarySemester,
    String? secondarySemester,
    List<Course> availableCourses,
  ) async {
    try {
      // Get discipline electives for primary branch
      List<DisciplineElective> electives = await getDisciplineElectives(primaryBranch);
      
      // If secondary branch is selected, get its electives too
      if (secondaryBranch != null && secondaryBranch.isNotEmpty) {
        final secondaryElectives = await getDisciplineElectives(secondaryBranch);
        electives.addAll(secondaryElectives);
      }
      
      // Get primary branch code from name
      String? primaryBranchCode = _getBranchCodeFromName(primaryBranch);
      String? secondaryBranchCode = secondaryBranch != null ? _getBranchCodeFromName(secondaryBranch) : null;
      
      if (primaryBranchCode == null) {
        print('Could not find branch code for: $primaryBranch');
        // Fallback to original filtering without clash detection
        return getFilteredDisciplineElectives(primaryBranch, secondaryBranch, availableCourses);
      }
      
      // Get core courses for clash detection
      final coreCourseCodes = await _getCoreCourseCodes(
        primarySemester,
        primaryBranchCode,
        secondarySemester,
        secondaryBranchCode,
      );
      
      print('Found ${coreCourseCodes.length} core courses for clash detection');
      
      // Filter to only include courses that exist in the available courses and don't clash
      final availableCourseCodes = availableCourses.map((c) => c.courseCode).toSet();
      
      final filteredElectives = <DisciplineElective>[];
      for (final elective in electives) {
        // Check if course exists in available courses
        if (!availableCourseCodes.contains(elective.courseCode)) {
          continue;
        }
        
        // Check for clashes if we have core courses
        if (coreCourseCodes.isNotEmpty) {
          final course = availableCourses.firstWhere((c) => c.courseCode == elective.courseCode);
          if (_doesCourseClashWithCore(course, coreCourseCodes, availableCourses)) {
            print('Discipline elective ${elective.courseCode} clashes with core courses, excluding');
            continue;
          }
        }
        
        filteredElectives.add(elective);
      }
      
      // Remove duplicates (in case both branches have same electives)
      final uniqueElectives = <String, DisciplineElective>{};
      for (final elective in filteredElectives) {
        uniqueElectives[elective.courseCode] = elective;
      }
      
      final result = uniqueElectives.values.toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));
      
      print('Filtered to ${result.length} non-clashing discipline electives');
      return result;
    } catch (e) {
      throw Exception('Failed to filter discipline electives with clash detection: $e');
    }
  }

  // Helper method to get branch code from branch name
  String? _getBranchCodeFromName(String branchName) {
    for (final entry in _branchCodeToName.entries) {
      if (entry.value == branchName) {
        return entry.key;
      }
    }
    return null;
  }

  // Get core course codes for specified branches and semesters (reused from humanities service)
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

  // Add core courses for a specific branch and semester (reused from humanities service)
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

  // Check if a discipline elective course clashes with any core course (reused from humanities service)
  bool _doesCourseClashWithCore(
    Course electiveCourse,
    Set<String> coreCourseCodes,
    List<Course> availableCourses,
  ) {
    // Find core courses in the available courses list
    final coreCourses = availableCourses
        .where((course) => coreCourseCodes.contains(course.courseCode))
        .toList();

    // Check if elective course sections clash with any core course sections
    for (final electiveSection in electiveCourse.sections) {
      for (final coreCoreCourse in coreCourses) {
        for (final coreSection in coreCoreCourse.sections) {
          if (_doSectionsClash(electiveSection, coreSection)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  // Check if two sections have time clashes (reused from humanities service)
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

  // Get course details for a discipline elective
  Course? getCourseDetails(String courseCode, List<Course> availableCourses) {
    try {
      return availableCourses.firstWhere(
        (course) => course.courseCode == courseCode,
      );
    } catch (e) {
      return null;
    }
  }
}

class BranchInfo {
  final String name;
  final String code;
  
  BranchInfo({
    required this.name,
    required this.code,
  });
  
  @override
  String toString() => name;
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BranchInfo && other.name == name && other.code == code;
  }
  
  @override
  int get hashCode => name.hashCode ^ code.hashCode;
}

class DisciplineElective {
  final String courseCode;
  final String courseName;
  final String branchName;
  
  DisciplineElective({
    required this.courseCode,
    required this.courseName,
    required this.branchName,
  });
  
  @override
  String toString() => '$courseCode - $courseName';
}