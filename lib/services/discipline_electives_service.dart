import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import 'secure_logger.dart';

class DisciplineElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mapping from branch codes to full branch names (same as humanities service)
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
  
  // Get all available branches
  Future<List<BranchInfo>> getAvailableBranches() async {
    try {
      SecureLogger.info('DISCIPLINE', 'Fetching metadata from Firestore');
      final metadataDoc = await _firestore
          .collection('discipline_electives')
          .doc('_metadata')
          .get()
          .timeout(Duration(seconds: 10));
      
      SecureLogger.info('DISCIPLINE', 'Metadata document status', {
        'exists': metadataDoc.exists
      });
      
      if (!metadataDoc.exists) {
        SecureLogger.warning('DISCIPLINE', 'Metadata not found, using fallback data');
        return _getFallbackBranches();
      }
      
      final data = metadataDoc.data()!;
      SecureLogger.debug('DISCIPLINE', 'Metadata keys found', {
        'keyCount': data.keys.length
      });
      
      if (data.containsKey('branchCodes')) {
        final branchCodes = data['branchCodes'] as List<dynamic>;
        SecureLogger.info('DISCIPLINE', 'Branch codes loaded', {
          'branchCount': branchCodes.length
        });
        
        final branches = branchCodes.map((branch) => BranchInfo(
          name: branch['name'] as String,
          code: branch['code'] as String,
        )).toList();
        
        SecureLogger.info('DISCIPLINE', 'Branches parsed successfully', {
          'branchCount': branches.length
        });
        return branches;
      } else {
        SecureLogger.warning('DISCIPLINE', 'branchCodes key not found, using fallback');
        return _getFallbackBranches();
      }
    } catch (e) {
      SecureLogger.error('DISCIPLINE', 'Error loading branches, using fallback data', e);
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
  
  // Get all discipline electives without clash checking
  Future<List<DisciplineElective>> getAllDisciplineElectives(
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
      
      final result = uniqueElectives.values.toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));
      
      SecureLogger.info('DISCIPLINE', 'Found discipline electives without clash filtering', {
        'electiveCount': result.length
      });
      return result;
    } catch (e) {
      throw Exception('Failed to get all discipline electives: $e');
    }
  }

  // Get discipline electives for a branch
  Future<List<DisciplineElective>> getDisciplineElectives(String branchName) async {
    try {
      SecureLogger.info('DISCIPLINE', 'Fetching discipline electives for branch', {
        'branchName': branchName
      });
      
      // Convert branch name to document ID
      final branchId = branchName.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '-');
      
      SecureLogger.debug('DISCIPLINE', 'Branch ID generated', {
        'branchId': branchId
      });
      
      final doc = await _firestore
          .collection('discipline_electives')
          .doc(branchId)
          .get()
          .timeout(Duration(seconds: 10));
      
      SecureLogger.debug('DISCIPLINE', 'Document existence check', {
        'exists': doc.exists
      });
      
      if (!doc.exists) {
        SecureLogger.warning('DISCIPLINE', 'Document not found, returning empty list');
        return [];
      }
      
      final data = doc.data()!;
      SecureLogger.debug('DISCIPLINE', 'Document data keys', {
        'keyCount': data.keys.length
      });
      
      if (!data.containsKey('courses')) {
        SecureLogger.warning('DISCIPLINE', 'No courses field found, returning empty list');
        return [];
      }
      
      final courses = data['courses'] as List<dynamic>;
      SecureLogger.info('DISCIPLINE', 'Found courses for branch', {
        'courseCount': courses.length
      });
      
      return courses.map((course) => DisciplineElective(
        courseCode: course['course_code'] as String,
        courseName: course['course_name'] as String,
        branchName: branchName,
      )).toList();
    } catch (e) {
      SecureLogger.error('DISCIPLINE', 'Error in getDisciplineElectives', e);
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
        SecureLogger.warning('DISCIPLINE', 'Could not find branch code', {
        'primaryBranch': primaryBranch
      });
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
      
      SecureLogger.info('DISCIPLINE', 'Found core courses for clash detection', {
        'coreCoursesCount': coreCourseCodes.length
      });
      
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
            SecureLogger.debug('DISCIPLINE', 'Discipline elective clashes with core courses, excluding', {
              'courseCode': elective.courseCode
            });
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
      
      SecureLogger.info('DISCIPLINE', 'Filtered to non-clashing discipline electives', {
        'filteredCount': result.length
      });
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
        SecureLogger.warning('DISCIPLINE', 'Course guide not found for semester', {
          'semesterDocId': semesterDocId
        });
        return;
      }

      final data = courseGuideDoc.data();
      if (data == null || !data.containsKey('groups')) {
        SecureLogger.warning('DISCIPLINE', 'No groups found in course guide for semester', {
          'semesterDocId': semesterDocId
        });
        return;
      }

      final groups = data['groups'] as Map<String, dynamic>;

      // Convert branch code to branch name
      final branchName = _branchCodeToName[branch];
      if (branchName == null) {
        SecureLogger.warning('DISCIPLINE', 'Unknown branch code', {
          'branchCode': branch
        });
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
          SecureLogger.info('DISCIPLINE', 'Found group for branch', {
            'branchCode': branch,
            'branchName': branchName,
            'courseCount': courses.length
          });
        }
      }

      SecureLogger.info('DISCIPLINE', 'Added core courses for branch and semester', {
        'totalCoreCoursesCount': coreCourseCodes.length,
        'branchCode': branch,
        'semester': semester
      });
    } catch (e) {
      SecureLogger.error('DISCIPLINE', 'Error getting core courses', e, null, {
        'branchCode': branch,
        'semester': semester
      });
    }
  }

  // Check if a discipline elective course clashes with any core course
  bool _doesCourseClashWithCore(
    Course electiveCourse,
    Set<String> coreCourseCodes,
    List<Course> availableCourses,
  ) {
    // Find core courses in the available courses list
    final coreCourses = availableCourses
        .where((course) => coreCourseCodes.contains(course.courseCode))
        .toList();

    // First check exam clashes
    for (final coreCourse in coreCourses) {
      if (_hasExamClash(electiveCourse, coreCourse)) {
        SecureLogger.debug('DISCIPLINE', 'Discipline elective has exam clash with core course', {
          'electiveCourseCode': electiveCourse.courseCode,
          'coreCourseCode': coreCourse.courseCode
        });
        return true;
      }
    }

    // Then check time clashes with section-type awareness
    // Group elective sections by type
    final electiveLectures = electiveCourse.sections.where((s) => s.type == SectionType.L).toList();
    final electivePracticals = electiveCourse.sections.where((s) => s.type == SectionType.P).toList();
    final electiveTutorials = electiveCourse.sections.where((s) => s.type == SectionType.T).toList();

    for (final coreCourse in coreCourses) {
      // Group core course sections by type
      final coreLectures = coreCourse.sections.where((s) => s.type == SectionType.L).toList();
      final corePracticals = coreCourse.sections.where((s) => s.type == SectionType.P).toList();
      final coreTutorials = coreCourse.sections.where((s) => s.type == SectionType.T).toList();

      // Check if ALL sections of same type clash (means no viable option)
      if (_allSectionsClash(electiveLectures, coreLectures) ||
          _allSectionsClash(electivePracticals, corePracticals) ||
          _allSectionsClash(electiveTutorials, coreTutorials)) {
        SecureLogger.debug('DISCIPLINE', 'Discipline elective has unavoidable time clash with core course', {
          'electiveCourseCode': electiveCourse.courseCode,
          'coreCourseCode': coreCourse.courseCode
        });
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