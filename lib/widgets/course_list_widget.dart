import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/course.dart';
import '../models/timetable.dart';
import '../utils/course_utils.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/campus_service.dart';
import '../services/core/clash_detector.dart';
import '../utils/design_constants.dart';

class CourseListWidget extends StatelessWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String courseCode, String sectionId, bool isSelected) onSectionToggle;
  final bool showOnlySelected;

  CourseListWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
    this.showOnlySelected = false,
  });

  late final Set<String> _selectedKeys = {
    for (final s in selectedSections) '${s.courseCode}|${s.sectionId}',
  };

  late final Set<String> _selectedTypeKeys = {
    for (final s in selectedSections) '${s.courseCode}|${s.section.type}',
  };

  // Built once per widget instance rather than per tile. _getCourseClashes runs
  // for every visible row, and it used to resolve each selected section's course
  // with a firstWhere over the ~2,800-course list — O(rows x selected x catalog)
  // on every scroll. The index makes the lookup O(1); _selectedCourses caches
  // the resolved set the exam checks iterate.
  late final Map<String, Course> _courseIndex = {
    for (final c in courses) c.courseCode: c,
  };

  late final List<Course> _selectedCourses = {
    for (final s in selectedSections) s.courseCode,
  }.map((code) => _courseIndex[code]).whereType<Course>().toList();

  bool _isSectionSelected(String courseCode, String sectionId) {
    return _selectedKeys.contains('$courseCode|$sectionId');
  }

  bool _isSectionTypeAlreadySelected(String courseCode, SectionType type) {
    return _selectedTypeKeys.contains('$courseCode|$type');
  }

  /// Returns a human-readable conflict description for this specific section,
  /// or null if no conflict.
  String? _getSectionConflict(Section section, String courseCode) {
    if (selectedSections.isEmpty) return null;
    final otherSections = selectedSections
        .where((s) => s.courseCode != courseCode)
        .toList();
    if (otherSections.isEmpty) return null;

    final conflicts = ClashDetector.checkScheduleConflicts(section, otherSections);
    if (conflicts.isEmpty) return null;

    final first = conflicts.first;
    return 'Clashes with ${first.conflictingCourse} ${first.conflictingSectionId} (${first.time})';
  }

  String _getSelectedSectionsText(String courseCode) {
    final courseSections = selectedSections
        .where((s) => s.courseCode == courseCode)
        .toList();

    if (courseSections.isEmpty) return '';

    final Map<SectionType, String> typeToSection = {};
    for (final section in courseSections) {
      typeToSection[section.section.type] = section.sectionId;
    }

    final List<String> parts = [];
    for (final type in [SectionType.L, SectionType.T, SectionType.P]) {
      if (typeToSection.containsKey(type)) {
        parts.add('${typeToSection[type]}');
      }
    }

    return parts.join(' ');
  }

  /// Check if a course clashes with already-selected courses (exam or schedule).
  List<String> _getCourseClashes(Course course) {
    if (selectedSections.isEmpty) return [];
    if (selectedSections.any((s) => s.courseCode == course.courseCode)) return [];

    final clashes = <String>[];

    // Check mid-sem exam clashes
    if (course.midSemExam != null) {
      for (final selectedCourse in _selectedCourses) {
        if (selectedCourse.courseCode == course.courseCode) continue;
        if (selectedCourse.midSemExam != null &&
            ClashDetector.examDatesConflict(course.midSemExam!, selectedCourse.midSemExam!)) {
          clashes.add('MidSem clash with ${selectedCourse.courseCode}');
          break;
        }
      }
    }

    // Check end-sem/comprehensive exam clashes
    if (course.endSemExam != null) {
      for (final selectedCourse in _selectedCourses) {
        if (selectedCourse.courseCode == course.courseCode) continue;
        if (selectedCourse.endSemExam != null &&
            ClashDetector.examDatesConflict(course.endSemExam!, selectedCourse.endSemExam!)) {
          clashes.add('Compre clash with ${selectedCourse.courseCode}');
          break;
        }
      }
    }

    // Check each section type individually — are ALL sections of that type blocked?
    final sectionsByType = <SectionType, List<Section>>{};
    for (final section in course.sections) {
      sectionsByType.putIfAbsent(section.type, () => []).add(section);
    }

    for (final entry in sectionsByType.entries) {
      final type = entry.key;
      final sections = entry.value;
      final allBlocked = sections.every((section) {
        final conflicts = ClashDetector.checkScheduleConflicts(section, selectedSections);
        return conflicts.isNotEmpty;
      });
      if (allBlocked) {
        final typeName = type == SectionType.L ? 'Lecture' :
                         type == SectionType.P ? 'Practical' : 'Tutorial';
        clashes.add('All $typeName sections clash');
      }
    }

    return clashes;
  }

  @override
  Widget build(BuildContext context) {
    List<Course> displayCourses;

    if (showOnlySelected) {
      final selectedCodes = <String>{for (final s in selectedSections) s.courseCode};
      displayCourses = courses.where((course) =>
        selectedCodes.contains(course.courseCode)
      ).toList();
    } else {
      displayCourses = courses;
    }

    if (displayCourses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showOnlySelected ? Icons.school_outlined : Icons.search_off,
              size: 64,
              color: AppDesign.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              showOnlySelected ? 'No courses selected' : 'No courses found',
              style: TextStyle(
                fontSize: 16,
                color: AppDesign.muted(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showOnlySelected
                ? 'Go to Search tab to add courses'
                : 'Try adjusting your search criteria',
              style: TextStyle(
                fontSize: 12,
                color: AppDesign.muted(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      // Pre-build extra rows off-screen so fast wheel/trackpad scrolling
      // doesn't reveal blank gaps before items paint.
      scrollCacheExtent: ScrollCacheExtent.pixels(800),
      padding: ResponsiveService.getAdaptivePadding(
        context,
        EdgeInsets.fromLTRB(
          8,
          8,
          8,
          ResponsiveService.isMobile(context) ? 100 : 8
        ),
      ),
      itemCount: displayCourses.length,
      itemBuilder: (context, index) {
        final course = displayCourses[index];
        final isSelectedCourse = selectedSections.any(
          (s) => s.courseCode == course.courseCode,
        );
        final clashes = _getCourseClashes(course);
        final hasClashes = clashes.isNotEmpty;

        return Opacity(
          opacity: hasClashes ? 0.5 : 1.0,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: hasClashes
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : (isSelectedCourse && !showOnlySelected)
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: hasClashes
                ? Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3))
                : (isSelectedCourse && !showOnlySelected)
                  ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: (isSelectedCourse && !showOnlySelected) ? 6 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                ExpansionTile(
                  title: Row(
                    children: [
                      if (isSelectedCourse && !showOnlySelected) ...[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          course.courseCode,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: hasClashes
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow)
                              : (isSelectedCourse && !showOnlySelected)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (course.courseTitle.isNotEmpty && course.courseTitle != course.courseCode)
                        Text(course.courseTitle),
                      Text('Instructor in Charge: ${CourseUtils.getInstructorInCharge(course)}',
                           style: TextStyle(
                             color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                           )),
                      Text('Credits: L${course.lectureCredits} P${course.practicalCredits} U${course.totalCredits}'),
                      if (course.midSemExam != null)
                        Text('MidSem: ${course.midSemExam!.date.day}/${course.midSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot, campus: CampusService.currentCampusCode)}'),
                      if (course.endSemExam != null)
                        Text('EndSem: ${course.endSemExam!.date.day}/${course.endSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot, campus: CampusService.currentCampusCode)}'),
                      if (_getSelectedSectionsText(course.courseCode).isNotEmpty)
                        Text(
                          'Selected: ${_getSelectedSectionsText(course.courseCode)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  children: course.sections.map((section) {
                    final isSelected = _isSectionSelected(course.courseCode, section.sectionId);
                    final isTypeAlreadySelected = _isSectionTypeAlreadySelected(course.courseCode, section.type);
                    final canSelect = isSelected || !isTypeAlreadySelected;
                    final sectionConflict = isSelected ? null : _getSectionConflict(section, course.courseCode);
                    final isBlocked = !canSelect || sectionConflict != null;

                    return Container(
                      constraints: BoxConstraints(
                        minHeight: ResponsiveService.getTouchTargetSize(context),
                      ),
                      child: ListTile(
                        title: Text(
                          '${section.sectionId} - ${section.instructor}',
                          style: TextStyle(
                            color: isBlocked && !isSelected ? AppDesign.muted(context) : null,
                            fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                          ),
                        ),
                        contentPadding: ResponsiveService.getAdaptivePadding(
                          context,
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Room: ${section.room}',
                              style: TextStyle(color: isBlocked && !isSelected ? AppDesign.muted(context) : null),
                            ),
                            Text(
                              'Schedule: ${TimeSlotInfo.getFormattedSchedule(section.schedule)}',
                              style: TextStyle(color: isBlocked && !isSelected ? AppDesign.muted(context) : null),
                            ),
                            if (!canSelect && !isSelected)
                              Text(
                                'Already selected ${section.type.name} section for this course',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                                  fontSize: 12
                                ),
                              ),
                            if (sectionConflict != null && canSelect)
                              Text(
                                sectionConflict,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 70,
                          height: 32,
                          child: TextButton(
                            onPressed: (!isBlocked || isSelected) ? () {
                              onSectionToggle(course.courseCode, section.sectionId, isSelected);
                            } : null,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: isSelected
                                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.1)
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              isSelected ? 'Remove' : 'Add',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (!isBlocked || isSelected)
                                  ? (isSelected
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary)
                                  : AppDesign.muted(context),
                              ),
                            ),
                          ),
                        ),
                        tileColor: isSelected
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                          : (isBlocked ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.3) : null),
                      ),
                    );
                  }).toList(),
                ),
                if (hasClashes)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            clashes.join(' • '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
