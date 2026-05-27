import '../../models/course.dart';
import '../../models/timetable.dart';
import 'branch_structure_service.dart';

class AutoLoadCDCService {
  static final AutoLoadCDCService _instance = AutoLoadCDCService._internal();
  factory AutoLoadCDCService() => _instance;
  AutoLoadCDCService._internal();

  final BranchStructureService _branchService = BranchStructureService();

  Future<List<SelectedSection>> loadCDCsForBranchAndSemester({
    required String branch,
    required String semester,
    required List<Course> availableCourses,
  }) async {
    try {
      final cdcCodes = await _branchService.getCDCs(branch, semester);

      final selectedSections = <SelectedSection>[];

      for (final code in cdcCodes) {
        final course = availableCourses.where((c) => c.courseCode == code).firstOrNull;
        if (course != null) {
          final lectureSections = course.sections.where((s) => s.type == SectionType.L).toList();
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
