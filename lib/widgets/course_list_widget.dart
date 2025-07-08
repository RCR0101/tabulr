import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_utils.dart';

class CourseListWidget extends StatelessWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String courseCode, String sectionId, bool isSelected) onSectionToggle;

  const CourseListWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
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

  @override
  Widget build(BuildContext context) {
    // Separate courses into selected and non-selected
    final selectedCourses = <Course>[];
    final nonSelectedCourses = <Course>[];
    
    for (final course in courses) {
      final hasSelectedSections = selectedSections.any(
        (s) => s.courseCode == course.courseCode,
      );
      
      if (hasSelectedSections) {
        selectedCourses.add(course);
      } else {
        nonSelectedCourses.add(course);
      }
    }
    
    // Combine lists with selected courses first
    final sortedCourses = [...selectedCourses, ...nonSelectedCourses];
    
    // Calculate item count including divider
    final totalItems = sortedCourses.length + (selectedCourses.isNotEmpty && nonSelectedCourses.isNotEmpty ? 1 : 0);
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Check if this is the divider position
        if (selectedCourses.isNotEmpty && nonSelectedCourses.isNotEmpty && index == selectedCourses.length) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Other Courses (${nonSelectedCourses.length})',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          );
        }
        
        // Adjust index for course items after divider
        final courseIndex = index > selectedCourses.length ? index - 1 : index;
        final course = sortedCourses[courseIndex];
        final isSelectedCourse = selectedCourses.contains(course);
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelectedCourse 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: isSelectedCourse 
              ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))
              : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: isSelectedCourse ? 6 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ExpansionTile(
            title: Row(
              children: [
                if (isSelectedCourse) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
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
                      color: isSelectedCourse 
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
              ],
            ),
            children: course.sections.map((section) {
              final isSelected = _isSectionSelected(course.courseCode, section.sectionId);
              final isTypeAlreadySelected = _isSectionTypeAlreadySelected(course.courseCode, section.type);
              final canSelect = isSelected || !isTypeAlreadySelected;
              
              return ListTile(
                title: Text(
                  '${section.sectionId} - ${section.instructor}',
                  style: TextStyle(
                    color: canSelect ? null : Colors.grey,
                  ),
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
                          color: Theme.of(context).colorScheme.error.withOpacity(0.8), 
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
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15) 
                  : (!canSelect ? Theme.of(context).colorScheme.surface.withOpacity(0.3) : null),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}