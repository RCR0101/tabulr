import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_data_service.dart';
import '../widgets/search_filter_widget.dart';

class AddSwapScreen extends StatefulWidget {
  final List<SelectedSection> currentSelectedSections;
  final List<Course> availableCourses;
  final String currentCampus;

  const AddSwapScreen({
    super.key,
    required this.currentSelectedSections,
    required this.availableCourses,
    required this.currentCampus,
  });

  @override
  State<AddSwapScreen> createState() => _AddSwapScreenState();
}

class _AddSwapScreenState extends State<AddSwapScreen> {
  final CourseDataService _courseDataService = CourseDataService();
  
  List<Course> _availableCourses = [];
  List<Course> _filteredCourses = [];
  Map<String, Map<SectionType, String>> _selectedSections = {}; // courseCode -> {type -> sectionId}
  List<ValidationResult> _validationResults = [];
  bool _isLoading = true;
  bool _isValidating = false;
  String _searchQuery = '';
  String? _selectedDiscipline;
  String? _selectedLevel;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final courses = await _courseDataService.fetchCourses();
      setState(() {
        _availableCourses = courses;
        _filteredCourses = courses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading courses: $e')),
        );
      }
    }
  }

  void _filterCourses() {
    setState(() {
      _filteredCourses = _availableCourses.where((course) {
        final matchesSearch = _searchQuery.isEmpty ||
            course.courseCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            course.courseTitle.toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesDiscipline = _selectedDiscipline == null ||
            course.courseCode.startsWith(_selectedDiscipline!);
        
        final matchesLevel = _selectedLevel == null ||
            course.courseCode.contains(_selectedLevel!);
        
        return matchesSearch && matchesDiscipline && matchesLevel;
      }).toList();
    });
  }

  Future<void> _validateSelection() async {
    if (_selectedSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one course section')),
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _validationResults = [];
    });

    try {
      final List<ValidationResult> results = [];
      
      for (final entry in _selectedSections.entries) {
        final courseCode = entry.key;
        final sectionsByType = entry.value;
        
        final course = _availableCourses.firstWhere((c) => c.courseCode == courseCode);
        
        for (final typeEntry in sectionsByType.entries) {
          final sectionType = typeEntry.key;
          final sectionId = typeEntry.value;
          
          final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
          
          final conflicts = _checkForConflicts(section);
          
          results.add(ValidationResult(
            courseCode: courseCode,
            sectionId: sectionId,
            sectionType: sectionType,
            courseTitle: course.courseTitle,
            canBeAdded: conflicts.isEmpty,
            conflicts: conflicts,
          ));
        }
      }
      
      setState(() {
        _validationResults = results;
        _isValidating = false;
      });
    } catch (e) {
      setState(() {
        _isValidating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error validating courses: $e')),
        );
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedSections.clear();
      _validationResults.clear();
    });
  }

  List<ConflictInfo> _checkForConflicts(Section section) {
    final conflicts = <ConflictInfo>[];
    
    for (final scheduleEntry in section.schedule) {
      for (final day in scheduleEntry.days) {
        for (final hour in scheduleEntry.hours) {
          for (final currentSelected in widget.currentSelectedSections) {
            for (final currentScheduleEntry in currentSelected.section.schedule) {
              if (currentScheduleEntry.days.contains(day) && currentScheduleEntry.hours.contains(hour)) {
                conflicts.add(ConflictInfo(
                  conflictingCourse: currentSelected.courseCode,
                  conflictingSectionId: currentSelected.sectionId,
                  day: day,
                  time: TimeSlotInfo.getHourSlotName(hour),
                ));
              }
            }
          }
        }
      }
    }
    
    return conflicts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add/Swap Courses'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Current courses section
                Expanded(
                  flex: 1,
                  child: _buildCurrentCoursesSection(),
                ),
                const VerticalDivider(width: 1),
                // New courses selection section
                Expanded(
                  flex: 1,
                  child: _buildNewCoursesSection(),
                ),
              ],
            ),
    );
  }

  Widget _buildCurrentCoursesSection() {
    // Group selected sections by course code
    final currentCourses = <String, List<SelectedSection>>{};
    for (final selectedSection in widget.currentSelectedSections) {
      currentCourses.putIfAbsent(selectedSection.courseCode, () => []).add(selectedSection);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          child: Row(
            children: [
              Icon(Icons.schedule, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Current Timetable',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: currentCourses.isEmpty
              ? const Center(
                  child: Text(
                    'No courses in current timetable',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: currentCourses.length,
                  itemBuilder: (context, index) {
                    final courseCode = currentCourses.keys.elementAt(index);
                    final selectedSections = currentCourses[courseCode]!;
                    
                    // Find course title from available courses
                    final course = widget.availableCourses.firstWhere(
                      (c) => c.courseCode == courseCode,
                      orElse: () => Course(
                        courseCode: courseCode,
                        courseTitle: 'Unknown Course',
                        lectureCredits: 0,
                        practicalCredits: 0,
                        totalCredits: 0,
                        sections: [],
                      ),
                    );
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              courseCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              course.courseTitle,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            // Show all selected sections for this course
                            ...selectedSections.map((selectedSection) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getSectionTypeColor(selectedSection.section.type),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        selectedSection.section.type.name,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Section ${selectedSection.sectionId}${selectedSection.section.instructor.isNotEmpty ? ' - ${selectedSection.section.instructor}' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getSectionTypeColor(SectionType type) {
    switch (type) {
      case SectionType.L:
        return Colors.blue;
      case SectionType.P:
        return Colors.orange;
      case SectionType.T:
        return Colors.green;
    }
  }

  Widget _buildNewCoursesSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Add/Swap Courses',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Search and filters
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SearchFilterWidget(
                onSearchChanged: (query, filters) {
                  _searchQuery = query;
                  _filterCourses();
                },
              ),
              const SizedBox(height: 16),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectedSections.isEmpty ? null : _clearSelection,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Selection'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isValidating ? null : _validateSelection,
                      icon: _isValidating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user),
                      label: Text(_isValidating ? 'Validating...' : 'Validate Selection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Course selection and validation results
        Expanded(
          child: _validationResults.isNotEmpty
              ? _buildValidationResults()
              : _buildCourseSelection(),
        ),
      ],
    );
  }

  Widget _buildCourseSelection() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredCourses.length,
      itemBuilder: (context, index) {
        final course = _filteredCourses[index];
        final courseSelections = _selectedSections[course.courseCode] ?? {};
        final hasSelections = courseSelections.isNotEmpty;
        
        // Group sections by type
        final Map<SectionType, List<Section>> sectionsByType = {};
        for (final section in course.sections) {
          sectionsByType.putIfAbsent(section.type, () => []).add(section);
        }
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(
              course.courseCode,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.courseTitle),
                if (hasSelections) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Selected: ${courseSelections.entries.map((e) => '${e.key.name}:${e.value}').join(', ')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            trailing: hasSelections
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.radio_button_unchecked),
            children: sectionsByType.entries.map((typeEntry) {
              final sectionType = typeEntry.key;
              final sections = typeEntry.value;
              final selectedSectionId = courseSelections[sectionType];
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '${_getSectionTypeName(sectionType)} Sections',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  ...sections.map((section) {
                    final isSelected = selectedSectionId == section.sectionId;
                    
                    return ListTile(
                      title: Text('Section ${section.sectionId}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (section.instructor.isNotEmpty)
                            Text('Instructor: ${section.instructor}'),
                          Text('Schedule: ${_formatSchedule(section.schedule)}'),
                        ],
                      ),
                      leading: Radio<String>(
                        value: section.sectionId,
                        groupValue: selectedSectionId,
                        onChanged: (value) {
                          setState(() {
                            if (value != null) {
                              _selectedSections.putIfAbsent(course.courseCode, () => {})[sectionType] = value;
                            } else {
                              _selectedSections[course.courseCode]?.remove(sectionType);
                              if (_selectedSections[course.courseCode]?.isEmpty == true) {
                                _selectedSections.remove(course.courseCode);
                              }
                            }
                            _validationResults.clear(); // Clear previous validation
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedSections[course.courseCode]?.remove(sectionType);
                            if (_selectedSections[course.courseCode]?.isEmpty == true) {
                              _selectedSections.remove(course.courseCode);
                            }
                          } else {
                            _selectedSections.putIfAbsent(course.courseCode, () => {})[sectionType] = section.sectionId;
                          }
                          _validationResults.clear(); // Clear previous validation
                        });
                      },
                    );
                  }),
                  const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _getSectionTypeName(SectionType type) {
    switch (type) {
      case SectionType.L:
        return 'Lecture';
      case SectionType.P:
        return 'Practical/Lab';
      case SectionType.T:
        return 'Tutorial';
    }
  }

  Widget _buildValidationResults() {
    return Column(
      children: [
        // Back to selection button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _validationResults.clear();
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Course Selection'),
            ),
          ),
        ),
        const Divider(),
        // Validation results
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _validationResults.length,
            itemBuilder: (context, index) {
              final result = _validationResults[index];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            result.canBeAdded ? Icons.check_circle : Icons.error,
                            color: result.canBeAdded ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${result.courseCode} - ${_getSectionTypeName(result.sectionType)} (${result.sectionId})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        result.courseTitle,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: result.canBeAdded
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: result.canBeAdded
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              result.canBeAdded ? Icons.thumb_up : Icons.warning,
                              size: 16,
                              color: result.canBeAdded ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                result.canBeAdded
                                    ? 'Can be safely added to timetable'
                                    : 'Has conflicts with existing courses',
                                style: TextStyle(
                                  color: result.canBeAdded ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (result.conflicts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Conflicts:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        ...result.conflicts.map((conflict) => Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.schedule, size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_getDayName(conflict.day)} at ${conflict.time} - conflicts with ${conflict.conflictingCourse} (${conflict.conflictingSectionId})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSchedule(List<ScheduleEntry> schedule) {
    return schedule.map((entry) {
      final days = entry.days.map(_getDayName).join('/');
      final hours = entry.hours.map((h) => TimeSlotInfo.getHourSlotName(h)).join(', ');
      return '$days: $hours';
    }).join(' | ');
  }

  String _getDayName(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.M: return 'Mon';
      case DayOfWeek.T: return 'Tue';
      case DayOfWeek.W: return 'Wed';
      case DayOfWeek.Th: return 'Thu';
      case DayOfWeek.F: return 'Fri';
      case DayOfWeek.S: return 'Sat';
    }
  }
}

class ValidationResult {
  final String courseCode;
  final String sectionId;
  final SectionType sectionType;
  final String courseTitle;
  final bool canBeAdded;
  final List<ConflictInfo> conflicts;

  ValidationResult({
    required this.courseCode,
    required this.sectionId,
    required this.sectionType,
    required this.courseTitle,
    required this.canBeAdded,
    required this.conflicts,
  });
}

class ConflictInfo {
  final String conflictingCourse;
  final String conflictingSectionId;
  final DayOfWeek day;
  final String time;

  ConflictInfo({
    required this.conflictingCourse,
    required this.conflictingSectionId,
    required this.day,
    required this.time,
  });
}