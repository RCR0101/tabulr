import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import '../utils/branch_constants.dart' as constants;

class ElectiveClashDetector {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<Set<String>> getCoreCourseCodes(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
  ) async {
    final coreCourseCodes = <String>{};

    await _addCoreCoursesForBranchSemester(
      coreCourseCodes,
      primarySemester,
      primaryBranch,
    );

    if (secondarySemester != null && secondaryBranch != null) {
      await _addCoreCoursesForBranchSemester(
        coreCourseCodes,
        secondarySemester,
        secondaryBranch,
      );
    }

    return coreCourseCodes;
  }

  static Future<void> _addCoreCoursesForBranchSemester(
    Set<String> coreCourseCodes,
    String semester,
    String branch,
  ) async {
    try {
      final semesterDocId = 'semester_${semester.replaceAll('-', '_')}';

      final courseGuideDoc = await _firestore
          .collection('reference').doc('course_guide').collection('semesters')
          .doc(semesterDocId)
          .get();

      if (!courseGuideDoc.exists) return;

      final data = courseGuideDoc.data();
      if (data == null || !data.containsKey('groups')) return;

      final rawGroups = data['groups'];

      final branchName = constants.branchCodeToName[branch];
      if (branchName == null) return;

      final groupsList = <Map<String, dynamic>>[];
      if (rawGroups is List) {
        for (final g in rawGroups) {
          if (g is Map<String, dynamic>) groupsList.add(g);
        }
      } else if (rawGroups is Map<String, dynamic>) {
        for (final entry in rawGroups.entries) {
          if (entry.value is Map<String, dynamic>) {
            groupsList.add(entry.value as Map<String, dynamic>);
          }
        }
      }

      for (final groupData in groupsList) {
        final branches = List<String>.from(groupData['branches'] ?? []);

        if (branches.contains(branchName)) {
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
    } catch (_) {}
  }

  static bool doesCourseClashWithCore(
    Course electiveCourse,
    Set<String> coreCourseCodes,
    List<Course> availableCourses,
  ) {
    final coreCourses = availableCourses
        .where((course) => coreCourseCodes.contains(course.courseCode))
        .toList();

    for (final coreCourse in coreCourses) {
      if (_hasExamClash(electiveCourse, coreCourse)) {
        return true;
      }
    }

    final electiveLectures = electiveCourse.sections.where((s) => s.type == SectionType.L).toList();
    final electivePracticals = electiveCourse.sections.where((s) => s.type == SectionType.P).toList();
    final electiveTutorials = electiveCourse.sections.where((s) => s.type == SectionType.T).toList();

    for (final coreCourse in coreCourses) {
      final coreLectures = coreCourse.sections.where((s) => s.type == SectionType.L).toList();
      final corePracticals = coreCourse.sections.where((s) => s.type == SectionType.P).toList();
      final coreTutorials = coreCourse.sections.where((s) => s.type == SectionType.T).toList();

      if (_allSectionsClash(electiveLectures, coreLectures) ||
          _allSectionsClash(electivePracticals, corePracticals) ||
          _allSectionsClash(electiveTutorials, coreTutorials)) {
        return true;
      }
    }

    return false;
  }

  static bool _hasExamClash(Course course1, Course course2) {
    if (course1.midSemExam != null && course2.midSemExam != null) {
      if (_examTimesConflict(course1.midSemExam!, course2.midSemExam!)) {
        return true;
      }
    }
    if (course1.endSemExam != null && course2.endSemExam != null) {
      if (_examTimesConflict(course1.endSemExam!, course2.endSemExam!)) {
        return true;
      }
    }
    return false;
  }

  static bool _examTimesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    return exam1.date.day == exam2.date.day &&
        exam1.date.month == exam2.date.month &&
        exam1.date.year == exam2.date.year &&
        exam1.timeSlot == exam2.timeSlot;
  }

  static bool _allSectionsClash(List<Section> sections1, List<Section> sections2) {
    if (sections1.isEmpty || sections2.isEmpty) {
      return false;
    }

    for (final section1 in sections1) {
      bool hasNonClashingOption = false;
      for (final section2 in sections2) {
        if (!_doSectionsClash(section1, section2)) {
          hasNonClashingOption = true;
          break;
        }
      }
      if (hasNonClashingOption) {
        return false;
      }
    }

    return true;
  }

  static bool _doSectionsClash(Section section1, Section section2) {
    for (final schedule1 in section1.schedule) {
      for (final schedule2 in section2.schedule) {
        final commonDays = schedule1.days.toSet().intersection(schedule2.days.toSet());
        if (commonDays.isNotEmpty) {
          final commonHours = schedule1.hours.toSet().intersection(schedule2.hours.toSet());
          if (commonHours.isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
