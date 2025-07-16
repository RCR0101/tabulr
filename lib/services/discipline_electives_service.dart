import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';

class DisciplineElectivesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
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