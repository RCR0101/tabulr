import '../../models/cdc_slot.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';
import 'branch_structure_service.dart';

class AutoLoadCDCService {
  static final AutoLoadCDCService _instance = AutoLoadCDCService._internal();
  factory AutoLoadCDCService() => _instance;
  AutoLoadCDCService._internal();

  final BranchStructureService _branchService = BranchStructureService();

  /// Picks a non-conflicting lecture section for each CDC of the student's
  /// degree at [semester].
  ///
  /// [secondaryBranch] makes this dual-degree aware: the combination's own CDC
  /// list is used rather than the union of the two branches, which would be
  /// wrong for both content and year (BE courses shift two years later).
  ///
  /// [chosen] answers the optional CDCs — the slots offering a choice of course
  /// (see [CdcSlot]). An unanswered choice loads nothing, because loading one
  /// alternative on the student's behalf puts a course they may not be taking
  /// on their timetable.
  /// The CDC course codes for this degree at [semester] that the campus
  /// actually offers.
  ///
  /// Codes rather than sections, because the generator picks sections itself:
  /// a course whose every section clashes with one already placed here is
  /// still a course the student has to take, and dropping it silently
  /// shortened the package it was asked to load.
  Future<List<String>> loadCDCCodesForDegree({
    required String primaryBranch,
    String? secondaryBranch,
    required String semester,
    required List<Course> availableCourses,
    Set<String> chosen = const {},
  }) async {
    final slots = await _branchService.getCoreCourseSlots(
      semester,
      primaryBranch,
      null,
      secondaryBranch,
    );
    final offered = {for (final c in availableCourses) c.courseCode};
    return [
      for (final code in CdcSlot.resolveSlots(slots, chosen))
        if (offered.contains(code)) code,
    ];
  }

  /// The component to place for [course]: its lectures, or — for a lab-only
  /// course like PHY U110 or CHEM U110 — whatever component it does have.
  ///
  /// Looking only at [SectionType.L] left every lab-only CDC out of the load,
  /// which is most of what a first-year credit-hours package is short of.
  List<Section> _primarySections(Course course) {
    for (final type in SectionType.values) {
      final sections = course.sections.where((s) => s.type == type).toList();
      if (sections.isNotEmpty) return sections;
    }
    return const [];
  }

  Future<List<SelectedSection>> loadCDCsForDegree({
    required String primaryBranch,
    String? secondaryBranch,
    required String semester,
    required List<Course> availableCourses,
    Set<String> chosen = const {},
  }) async {
    try {
      final cdcCodes = await loadCDCCodesForDegree(
        primaryBranch: primaryBranch,
        secondaryBranch: secondaryBranch,
        semester: semester,
        availableCourses: availableCourses,
        chosen: chosen,
      );

      final selectedSections = <SelectedSection>[];

      for (final code in cdcCodes) {
        final course = availableCourses.where((c) => c.courseCode == code).firstOrNull;
        if (course != null) {
          final lectureSections = _primarySections(course);
          for (final lectureSection in lectureSections) {
            final tempSection = SelectedSection(
              courseCode: course.courseCode,
              sectionId: lectureSection.sectionId,
              section: lectureSection,
            );

            bool hasConflict = false;
            for (final existing in selectedSections) {
              if (_hasTimeConflict(tempSection.section, existing.section)) {
                hasConflict = true;
                break;
              }
            }

            if (!hasConflict) {
              selectedSections.add(tempSection);
              break;
            }
          }
        }
      }

      return selectedSections;
    } catch (e) {
      rethrow;
    }
  }

  bool _hasTimeConflict(Section section1, Section section2) {
    for (final entry1 in section1.schedule) {
      for (final entry2 in section2.schedule) {
        final commonDays = entry1.days.where((day) => entry2.days.contains(day));
        if (commonDays.isNotEmpty) {
          final hours1 = Set.from(entry1.hours);
          final hours2 = Set.from(entry2.hours);
          if (hours1.intersection(hours2).isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
