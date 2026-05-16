import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import '../utils/branch_constants.dart' as constants;
import '../utils/elective_clash_utils.dart';

class DisciplineElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Map<String, String> _branchCodeToName = constants.branchCodeToName;
  
  // Get all available branches
  Future<List<BranchInfo>> getAvailableBranches() async {
    try {

      final metadataDoc = await _firestore
          .collection('discipline_electives')
          .doc('_metadata')
          .get()
          .timeout(Duration(seconds: 10));
      

      
      if (!metadataDoc.exists) {

        return _getFallbackBranches();
      }
      
      final data = metadataDoc.data()!;

      
      if (data.containsKey('branchCodes')) {
        final branchCodes = data['branchCodes'] as List<dynamic>;

        
        final branches = branchCodes.map((branch) => BranchInfo(
          name: branch['name'] as String,
          code: branch['code'] as String,
        )).toList();
        

        return branches;
      } else {

        return _getFallbackBranches();
      }
    } catch (e) {
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
      

      return result;
    } catch (e) {
      throw Exception('Failed to get all discipline electives: $e');
    }
  }

  // Get discipline electives for a branch
  Future<List<DisciplineElective>> getDisciplineElectives(String branchName) async {
    try {

      
      // Convert branch name to document ID
      final branchId = branchName.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '-');
      

      
      final doc = await _firestore
          .collection('discipline_electives')
          .doc(branchId)
          .get()
          .timeout(Duration(seconds: 10));
      

      
      if (!doc.exists) {

        return [];
      }
      
      final data = doc.data()!;

      
      if (!data.containsKey('courses')) {

        return [];
      }
      
      final courses = data['courses'] as List<dynamic>;

      
      return courses.map((course) => DisciplineElective(
        courseCode: course['course_code'] as String,
        courseName: course['course_name'] as String,
        branchName: branchName,
      )).toList();
    } catch (e) {

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

        // Fallback to original filtering without clash detection
        return getFilteredDisciplineElectives(primaryBranch, secondaryBranch, availableCourses);
      }
      
      // Get core courses for clash detection
      final coreCourseCodes = await ElectiveClashDetector.getCoreCourseCodes(
        primarySemester,
        primaryBranchCode,
        secondarySemester,
        secondaryBranchCode,
      );
      

      
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
          if (ElectiveClashDetector.doesCourseClashWithCore(course, coreCourseCodes, availableCourses)) {

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