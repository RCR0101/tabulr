import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_utils.dart';
import '../services/responsive_service.dart';

class CourseListWidget extends StatelessWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String courseCode, String sectionId, bool isSelected) onSectionToggle;
  final bool showOnlySelected;

  const CourseListWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
    this.showOnlySelected = false,
  });

  bool _isSectionSelected(String courseCode, String sectionId) {
    return selectedSections.any(
      (s) => s.courseCode == courseCode && s.sectionId == sectionId,
    );
  }

  bool _isSectionTypeAlreadySelected(String courseCode, SectionType type) {
    return selectedSections.any(
      (s) => s.courseCode == courseCode && s.section.type == type,
    );
  }

  String _getSelectedSectionsText(String courseCode) {
    final courseSections = selectedSections
        .where((s) => s.courseCode == courseCode)
        .toList();
    
    if (courseSections.isEmpty) return '';
    
    // Group by section type and get the section IDs
    final Map<SectionType, String> typeToSection = {};
    for (final section in courseSections) {
      typeToSection[section.section.type] = section.sectionId;
    }
    
    // Build the display string (e.g., "L1 T2 P3")
    final List<String> parts = [];
    for (final type in [SectionType.L, SectionType.T, SectionType.P]) {
      if (typeToSection.containsKey(type)) {
        parts.add('${typeToSection[type]}');
      }
    }
    
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    List<Course> displayCourses;
    
    if (showOnlySelected) {
      // Show only courses that have selected sections
      displayCourses = courses.where((course) => 
        selectedSections.any((s) => s.courseCode == course.courseCode)
      ).toList();
    } else {
      // Show all courses without any reordering
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
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              showOnlySelected ? 'No courses selected' : 'No courses found',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showOnlySelected 
                ? 'Go to Search tab to add courses' 
                : 'Try adjusting your search criteria',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
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
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: (isSelectedCourse && !showOnlySelected) 
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: (isSelectedCourse && !showOnlySelected) 
              ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
              : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: (isSelectedCourse && !showOnlySelected) ? 6 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ExpansionTile(
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
                      fontWeight: FontWeight.bold,
                      color: (isSelectedCourse && !showOnlySelected) 
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
                Text(course.courseTitle),
                Text('Instructor in Charge: ${CourseUtils.getInstructorInCharge(course)}',
                     style: TextStyle(
                       fontWeight: FontWeight.w500, 
                       color: Theme.of(context).colorScheme.primary,
                     )),
                Text('Credits: L${course.lectureCredits} P${course.practicalCredits} U${course.totalCredits}'),
                if (course.midSemExam != null)
                  Text('MidSem: ${course.midSemExam!.date.day}/${course.midSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot)}'),
                if (course.endSemExam != null)
                  Text('EndSem: ${course.endSemExam!.date.day}/${course.endSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot)}'),
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
              
              return Container(
                constraints: BoxConstraints(
                  minHeight: ResponsiveService.getTouchTargetSize(context),
                ),
                child: ListTile(
                  title: Text(
                    '${section.sectionId} - ${section.instructor}',
                    style: TextStyle(
                      color: canSelect ? null : Colors.grey,
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
                      style: TextStyle(color: canSelect ? null : Colors.grey),
                    ),
                    Text(
                      'Schedule: ${TimeSlotInfo.getFormattedSchedule(section.schedule)}',
                      style: TextStyle(color: canSelect ? null : Colors.grey),
                    ),
                    if (!canSelect && !isSelected)
                      Text(
                        'Already selected ${section.type.name} section for this course',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8), 
                          fontSize: 12
                        ),
                      ),
                  ],
                ),
                trailing: Switch(
                  value: isSelected,
                  onChanged: canSelect ? (value) {
                    onSectionToggle(course.courseCode, section.sectionId, isSelected);
                  } : null,
                ),
                tileColor: isSelected 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) 
                  : (!canSelect ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.3) : null),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}