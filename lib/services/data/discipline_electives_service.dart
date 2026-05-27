import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/course.dart';
import '../../utils/branch_constants.dart' as constants;
import 'branch_structure_service.dart';

class DisciplineElectivesService {
  final BranchStructureService _branchService = BranchStructureService();

  Future<List<BranchInfo>> getAvailableBranches() async {
    final codes = await _branchService.getAvailableBranches();
    return codes
        .map((code) => BranchInfo(
              name: constants.branchCodeToName[code] ?? code,
              code: code,
            ))
        .toList();
  }

  Future<List<DisciplineElective>> getDisciplineElectives(String branchCode) async {
    final dels = await _branchService.getDELs(branchCode);
    final branchName = constants.branchCodeToName[branchCode] ?? branchCode;
    return dels
        .map((code) => DisciplineElective(
              courseCode: code,
              courseName: '',
              branchName: branchName,
            ))
        .toList();
  }

  Future<List<DisciplineElective>> getAllDisciplineElectives(
    String primaryBranch,
    String? secondaryBranch,
    List<Course> availableCourses,
  ) async {
    final electives = await getDisciplineElectives(primaryBranch);

    if (secondaryBranch != null && secondaryBranch.isNotEmpty) {
      electives.addAll(await getDisciplineElectives(secondaryBranch));
    }

    final availableCodes = availableCourses.map((c) => c.courseCode).toSet();

    final unique = <String, DisciplineElective>{};
    for (final e in electives) {
      if (availableCodes.contains(e.courseCode)) {
        unique[e.courseCode] = e;
      }
    }

    return unique.values.toList()..sort((a, b) => a.courseCode.compareTo(b.courseCode));
  }

  Future<List<DisciplineElective>> getFilteredDisciplineElectives(
    String primaryBranch,
    String? secondaryBranch,
    List<Course> availableCourses,
  ) async {
    return getAllDisciplineElectives(primaryBranch, secondaryBranch, availableCourses);
  }

  Future<List<DisciplineElective>> getFilteredDisciplineElectivesWithClashDetection(
    String primaryBranch,
    String? secondaryBranch,
    String primarySemester,
    String? secondarySemester,
    List<Course> availableCourses,
  ) async {
    final electives = await getDisciplineElectives(primaryBranch);

    if (secondaryBranch != null && secondaryBranch.isNotEmpty) {
      electives.addAll(await getDisciplineElectives(secondaryBranch));
    }

    final coreCourseCodes = await _branchService.getCoreCourseCodes(
      primarySemester,
      primaryBranch,
      secondarySemester,
      secondaryBranch,
    );

    final availableCodes = availableCourses.map((c) => c.courseCode).toSet();
    final coreCourses = availableCourses
        .where((c) => coreCourseCodes.contains(c.courseCode))
        .toList();

    final filtered = <String, DisciplineElective>{};
    for (final elective in electives) {
      if (!availableCodes.contains(elective.courseCode)) continue;

      final course = availableCourses.firstWhere((c) => c.courseCode == elective.courseCode);
      if (_doesCourseClashWithCore(course, coreCourses)) continue;

      filtered[elective.courseCode] = elective;
    }

    return filtered.values.toList()..sort((a, b) => a.courseCode.compareTo(b.courseCode));
  }

  bool _doesCourseClashWithCore(Course elective, List<Course> coreCourses) {
    for (final core in coreCourses) {
      if (_hasExamClash(elective, core)) return true;
    }

    final eLectures = elective.sections.where((s) => s.type == SectionType.L).toList();
    final ePracticals = elective.sections.where((s) => s.type == SectionType.P).toList();
    final eTutorials = elective.sections.where((s) => s.type == SectionType.T).toList();

    for (final core in coreCourses) {
      final cL = core.sections.where((s) => s.type == SectionType.L).toList();
      final cP = core.sections.where((s) => s.type == SectionType.P).toList();
      final cT = core.sections.where((s) => s.type == SectionType.T).toList();

      if (_allSectionsClash(eLectures, cL) ||
          _allSectionsClash(ePracticals, cP) ||
          _allSectionsClash(eTutorials, cT)) {
        return true;
      }
    }
    return false;
  }

  bool _hasExamClash(Course c1, Course c2) {
    if (c1.midSemExam != null && c2.midSemExam != null) {
      if (_examTimesConflict(c1.midSemExam!, c2.midSemExam!)) return true;
    }
    if (c1.endSemExam != null && c2.endSemExam != null) {
      if (_examTimesConflict(c1.endSemExam!, c2.endSemExam!)) return true;
    }
    return false;
  }

  bool _examTimesConflict(ExamSchedule e1, ExamSchedule e2) {
    return e1.date.day == e2.date.day &&
        e1.date.month == e2.date.month &&
        e1.date.year == e2.date.year &&
        e1.timeSlot == e2.timeSlot;
  }

  bool _allSectionsClash(List<Section> s1, List<Section> s2) {
    if (s1.isEmpty || s2.isEmpty) return false;

    for (final sec1 in s1) {
      bool hasNonClashing = false;
      for (final sec2 in s2) {
        if (!_doSectionsClash(sec1, sec2)) {
          hasNonClashing = true;
          break;
        }
      }
      if (hasNonClashing) return false;
    }
    return true;
  }

  bool _doSectionsClash(Section s1, Section s2) {
    for (final sch1 in s1.schedule) {
      for (final sch2 in s2.schedule) {
        final commonDays = sch1.days.toSet().intersection(sch2.days.toSet());
        if (commonDays.isNotEmpty) {
          final commonHours = sch1.hours.toSet().intersection(sch2.hours.toSet());
          if (commonHours.isNotEmpty) return true;
        }
      }
    }
    return false;
  }

  Course? getCourseDetails(String courseCode, List<Course> availableCourses) {
    try {
      return availableCourses.firstWhere((c) => c.courseCode == courseCode);
    } catch (_) {
      return null;
    }
  }
}

class BranchInfo {
  final String name;
  final String code;

  BranchInfo({required this.name, required this.code});

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
