import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/course.dart';
import '../services/secure_logger.dart';
import 'branch_structure_service.dart';

class HumanitiesElectivesService {
  final BranchStructureService _branchService = BranchStructureService();

  Future<List<Course>> getAllHumanitiesElectives(List<Course> availableCourses) async {
    try {
      final branches = await _branchService.getAvailableBranches();

      final huelCodes = <String>{};
      for (final branch in branches) {
        final huels = await _branchService.getHUELs(branch);
        huelCodes.addAll(huels);
      }

      SecureLogger.debug('HUEL', 'Found ${huelCodes.length} unique HUEL course codes');

      final result = availableCourses
          .where((c) => huelCodes.contains(c.courseCode))
          .toList();

      SecureLogger.debug('HUEL', 'Found ${result.length} available HUEL courses');
      return result;
    } catch (e) {
      SecureLogger.error('HUEL', 'Error in getAllHumanitiesElectives', e);
      rethrow;
    }
  }

  Future<List<Course>> getFilteredHumanitiesElectives(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
    List<Course> availableCourses,
  ) async {
    try {
      final huels = await _branchService.getHUELs(primaryBranch);
      final huelCodes = <String>{...huels};

      if (secondaryBranch != null) {
        final secondaryHuels = await _branchService.getHUELs(secondaryBranch);
        huelCodes.addAll(secondaryHuels);
      }

      SecureLogger.debug('HUEL', 'Found ${huelCodes.length} HUEL course codes');

      final coreCourseCodes = await _branchService.getCoreCourseCodes(
        primarySemester,
        primaryBranch,
        secondarySemester,
        secondaryBranch,
      );

      SecureLogger.debug('HUEL', 'Found ${coreCourseCodes.length} core courses for filtering');

      final coreCourses = availableCourses
          .where((c) => coreCourseCodes.contains(c.courseCode))
          .toList();

      final filtered = <Course>[];
      for (final course in availableCourses) {
        if (!huelCodes.contains(course.courseCode)) continue;
        if (_doesCourseClashWithCore(course, coreCourses)) {
          SecureLogger.debug('HUEL', 'Course ${course.courseCode} clashes with core, excluding');
          continue;
        }
        filtered.add(course);
      }

      SecureLogger.debug('HUEL', 'Filtered to ${filtered.length} non-clashing HUEL courses');
      return filtered;
    } catch (e) {
      SecureLogger.error('HUEL', 'Error in getFilteredHumanitiesElectives', e);
      rethrow;
    }
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
      if (c1.midSemExam!.date.day == c2.midSemExam!.date.day &&
          c1.midSemExam!.date.month == c2.midSemExam!.date.month &&
          c1.midSemExam!.date.year == c2.midSemExam!.date.year &&
          c1.midSemExam!.timeSlot == c2.midSemExam!.timeSlot) {
        return true;
      }
    }
    if (c1.endSemExam != null && c2.endSemExam != null) {
      if (c1.endSemExam!.date.day == c2.endSemExam!.date.day &&
          c1.endSemExam!.date.month == c2.endSemExam!.date.month &&
          c1.endSemExam!.date.year == c2.endSemExam!.date.year &&
          c1.endSemExam!.timeSlot == c2.endSemExam!.timeSlot) {
        return true;
      }
    }
    return false;
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
}
