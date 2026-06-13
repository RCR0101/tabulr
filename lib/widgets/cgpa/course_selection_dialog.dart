import 'package:flutter/material.dart';
import '../../models/all_course.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../services/ui/responsive_service.dart';

class CourseSelectionDialog extends StatefulWidget {
  final List<Timetable> timetables;
  final List<String> semesters;

  const CourseSelectionDialog({
    super.key,
    required this.timetables,
    required this.semesters,
  });

  @override
  State<CourseSelectionDialog> createState() => _CourseSelectionDialogState();
}

class _CourseSelectionDialogState extends State<CourseSelectionDialog> {
  Timetable? _selectedTimetable;
  String? _selectedSemester;
  final Set<String> _selectedCourses = {};

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 16)),
      ),
      child: Container(
        width: isMobile ? double.infinity : 600,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.all(20)),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 16)),
                  topRight: Radius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 16)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.file_download_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import Courses from Timetable',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.all(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Timetable', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                          borderRadius: BorderRadius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 8)),
                        ),
                        child: DropdownButton<Timetable>(
                          value: _selectedTimetable,
                          isExpanded: true,
                          underline: Container(),
                          hint: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Choose a timetable'),
                          ),
                          onChanged: (timetable) {
                            setState(() {
                              _selectedTimetable = timetable;
                              _selectedCourses.clear();
                              _selectedSemester = null;
                            });
                          },
                          items: widget.timetables.asMap().entries.map((entry) {
                            final index = entry.key;
                            final timetable = entry.value;
                            String displayName = timetable.name.isNotEmpty && timetable.name != 'Untitled Timetable'
                                ? timetable.name
                                : 'Timetable ${index + 1}';
                            final courseCount = timetable.selectedSections.length;

                            return DropdownMenuItem<Timetable>(
                              value: timetable,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(displayName)),
                                    Text(
                                      '$courseCount course${courseCount != 1 ? 's' : ''}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (_selectedTimetable != null) ...[
                        const SizedBox(height: 24),
                        Text('Select Semester', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 8)),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedSemester,
                            isExpanded: true,
                            underline: Container(),
                            hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Choose a semester for all courses'),
                            ),
                            onChanged: (semester) {
                              setState(() => _selectedSemester = semester);
                            },
                            items: widget.semesters.map((semester) {
                              return DropdownMenuItem<String>(
                                value: semester,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(semester),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        if (_selectedSemester != null) ...[
                          const SizedBox(height: 24),
                          Text('Select Courses', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'All selected courses will be added to $_selectedSemester',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._buildCourseList(),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.all(16)),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedCourses.length} selected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _selectedCourses.isEmpty ? null : _importCourses,
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCourseList() {
    if (_selectedTimetable == null) return [];

    final uniqueCourses = <String, Course>{};
    for (final selectedSection in _selectedTimetable!.selectedSections) {
      if (!uniqueCourses.containsKey(selectedSection.courseCode)) {
        final course = _selectedTimetable!.availableCourses.firstWhere(
          (c) => c.courseCode == selectedSection.courseCode,
          orElse: () => Course(
            courseCode: selectedSection.courseCode,
            courseTitle: 'Unknown Course',
            lectureCredits: 0,
            practicalCredits: 0,
            totalCredits: 3,
            sections: [],
          ),
        );
        uniqueCourses[selectedSection.courseCode] = course;
      }
    }

    if (uniqueCourses.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No courses found in this timetable',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ];
    }

    return uniqueCourses.entries.map((entry) {
      final courseCode = entry.key;
      final course = entry.value;
      final isSelected = _selectedCourses.contains(courseCode);

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: isSelected ? 2 : 0,
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveService.getAdaptiveBorderRadius(context, 8)),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedCourses.add(courseCode);
                    } else {
                      _selectedCourses.remove(courseCode);
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(courseCode, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      course.courseTitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${course.totalCredits}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _importCourses() {
    if (_selectedTimetable == null || _selectedCourses.isEmpty || _selectedSemester == null) return;

    final coursesToImport = <String, List<AllCourse>>{};
    coursesToImport[_selectedSemester!] = [];

    for (final courseCode in _selectedCourses) {
      final course = _selectedTimetable!.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(
          courseCode: courseCode,
          courseTitle: 'Unknown Course',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 3,
          sections: [],
        ),
      );

      coursesToImport[_selectedSemester!]!.add(
        AllCourse(
          courseCode: course.courseCode,
          courseTitle: course.courseTitle,
          creditValue: course.totalCredits,
          type: 'Normal',
        ),
      );
    }

    Navigator.pop(context, coursesToImport);
  }
}
