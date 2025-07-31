import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../services/timetable_generator.dart';
import '../services/toast_service.dart';
import 'generated_timetable_card.dart';

class TimetableGeneratorWidget extends StatefulWidget {
  final List<Course> availableCourses;
  final Function(List<ConstraintSelectedSection>) onTimetableSelected;

  const TimetableGeneratorWidget({
    super.key,
    required this.availableCourses,
    required this.onTimetableSelected,
  });

  @override
  State<TimetableGeneratorWidget> createState() => _TimetableGeneratorWidgetState();
}

class _TimetableGeneratorWidgetState extends State<TimetableGeneratorWidget> {
  final List<String> _selectedCourses = [];
  final List<TimeAvoidance> _avoidTimes = [];
  final List<LabAvoidance> _avoidLabs = [];
  int _maxHoursPerDay = 8;
  final List<String> _preferredInstructors = [];
  final List<String> _avoidedInstructors = [];
  bool _avoidBackToBack = false;
  TimeSlot? _preferredExamSlot;
  List<GeneratedTimetable> _generatedTimetables = [];
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    
    if (isMobile) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                tabs: const [
                  Tab(icon: Icon(Icons.settings), text: 'Configure'),
                  Tab(icon: Icon(Icons.view_list), text: 'Results'),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Configuration Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                _buildConfigurationPanel(),
                                const SizedBox(height: 16),
                                _buildConstraintsPanel(),
                              ],
                            ),
                          ),
                        ),
                        _buildGenerateButton(),
                      ],
                    ),
                  ),
                  // Results Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildResultsPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // Desktop layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel - Configuration
        Expanded(
          flex: 1,
          child: Column(
            children: [
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      _buildConfigurationPanel(),
                      const SizedBox(height: 16),
                      _buildConstraintsPanel(),
                    ],
                  ),
                ),
              ),
              // Fixed generate button at bottom
              _buildGenerateButton(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right panel - Results
        Expanded(
          flex: 2,
          child: _buildResultsPanel(),
        ),
      ],
    );
  }

  Widget _buildConfigurationPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Course Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildCourseSelection(),
          ),
        ],
      ),
    );
  }

  Widget _buildConstraintsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Constraints & Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.view_list,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Generated Timetables',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_generatedTimetables.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_generatedTimetables.length} found',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _generatedTimetables.isEmpty
                ? _buildEmptyResults()
                : _buildGeneratedTimetables(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            _isGenerating ? 'Generating timetables...' : 'No timetables generated yet',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isGenerating 
                ? 'This may take a few moments'
                : 'Select courses and click Generate to see results',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 16),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Required Courses:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildCourseSearchField(),
        const SizedBox(height: 12),
        _buildSelectedCourseBadges(),
      ],
    );
  }

  Widget _buildCourseSearchField() {
    return TypeAheadField<Course>(
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Search courses by code or name...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        );
      },
      suggestionsCallback: (pattern) {
        if (pattern.isEmpty) return <Course>[];
        
        return widget.availableCourses.where((course) {
          final searchLower = pattern.toLowerCase();
          return course.courseCode.toLowerCase().contains(searchLower) ||
                 course.courseTitle.toLowerCase().contains(searchLower);
        }).take(10).toList();
      },
      itemBuilder: (context, course) {
        final isSelected = _selectedCourses.contains(course.courseCode);
        return ListTile(
          leading: Icon(
            isSelected ? Icons.check_circle : Icons.add_circle_outline,
            color: isSelected ? Colors.green : Colors.blue,
          ),
          title: Text(course.courseCode),
          subtitle: Text(
            course.courseTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${course.totalCredits} credits'),
        );
      },
      onSelected: (course) {
        setState(() {
          if (!_selectedCourses.contains(course.courseCode)) {
            _selectedCourses.add(course.courseCode);
          }
        });
      },
      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No courses found'),
      ),
    );
  }

  Widget _buildSelectedCourseBadges() {
    if (_selectedCourses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            'No courses selected',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedCourses.length > 6)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${_selectedCourses.length} courses selected • Scroll to see all',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedCourses.map((courseCode) {
            final course = widget.availableCourses.firstWhere(
              (c) => c.courseCode == courseCode,
              orElse: () => Course(
                courseCode: courseCode,
                courseTitle: 'Unknown',
                lectureCredits: 0,
                practicalCredits: 0,
                totalCredits: 0,
                sections: [],
              ),
            );
            
            return Chip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.courseCode,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    course.courseTitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () {
                setState(() {
                  _selectedCourses.remove(courseCode);
                });
              },
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              deleteIconColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
            );
          }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConstraints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constraints & Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Max hours per day:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: TextEditingController(text: _maxHoursPerDay.toString()),
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final hours = int.tryParse(value);
                    if (hours != null && hours > 0 && hours <= 12) {
                      _maxHoursPerDay = hours;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: CheckboxListTile(
            title: const Text(
              'Avoid back-to-back classes',
              style: TextStyle(fontSize: 14),
            ),
            value: _avoidBackToBack,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onChanged: (value) {
              setState(() {
                _avoidBackToBack = value ?? false;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Preferred exam slot:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<TimeSlot?>(
                  value: _preferredExamSlot,
                  hint: const Text('Any', style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  underline: Container(),
                  items: [
                    const DropdownMenuItem<TimeSlot?>(
                      value: null,
                      child: Text('Any', style: TextStyle(fontSize: 14)),
                    ),
                    ...TimeSlot.values.map((slot) => DropdownMenuItem(
                      value: slot,
                      child: Text(
                        TimeSlotInfo.getTimeSlotName(slot),
                        style: TextStyle(fontSize: 14),
                      ),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _preferredExamSlot = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTimeAvoidance(),
        const SizedBox(height: 16),
        _buildLabAvoidance(),
        const SizedBox(height: 16),
        _buildInstructorAvoidance(),
      ],
    );
  }

  Widget _buildTimeAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid time slots:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _addTimeAvoidance,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidTimes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidTimes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final avoidTime = entry.value;
                  return Chip(
                    label: Text(
                      '${avoidTime.day.name}: ${_formatAvoidTimeHours(avoidTime.hours)}',
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _avoidTimes.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    deleteIconColor: Colors.red,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLabAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid labs on:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _addLabAvoidance,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidLabs.isNotEmpty) ...[ 
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidLabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final avoidLab = entry.value;
                  return Chip(
                    label: Text(
                      '${avoidLab.day.name}: ${_formatAvoidTimeHours(avoidLab.hours)} (Labs)',
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _avoidLabs.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    deleteIconColor: Colors.red,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInstructorAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _selectedCourses.isNotEmpty ? _addInstructorAvoidance : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidedInstructors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidedInstructors.asMap().entries.map((entry) {
                  final index = entry.key;
                  final instructor = entry.value;
                  return Chip(
                    label: Text(
                      instructor,
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _avoidedInstructors.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    deleteIconColor: Colors.red,
                  );
                }).toList(),
              ),
            ),
          ),
        ] else if (_selectedCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
            ),
            child: const Text(
              'Select courses first to see available instructors',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  String _formatAvoidTimeHours(List<int> hours) {
    if (hours.isEmpty) return '';
    if (hours.length == 1) {
      return TimeSlotInfo.getHourSlotName(hours.first);
    }
    
    // Sort hours and format as range
    final sortedHours = [...hours]..sort();
    return TimeSlotInfo.getHourRangeName(sortedHours);
  }

  Future<void> _addTimeAvoidance() async {
    final result = await showDialog<TimeAvoidance>(
      context: context,
      builder: (context) => const _TimeAvoidanceDialog(),
    );
    
    if (result != null && mounted) {
      setState(() {
        _avoidTimes.add(result);
      });
    }
  }

  Future<void> _addLabAvoidance() async {
    final result = await showDialog<LabAvoidance>(
      context: context,
      builder: (context) => const _LabAvoidanceDialog(),
    );
    
    if (result != null && mounted) {
      setState(() {
        _avoidLabs.add(result);
      });
    }
  }

  Future<void> _addInstructorAvoidance() async {
    // Get instructors organized by course to avoid duplicates
    final Map<String, List<String>> courseInstructors = {};
    final Set<String> seenInstructorsLower = <String>{};
    
    for (final courseCode in _selectedCourses) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(
          courseCode: courseCode,
          courseTitle: 'Unknown',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 0,
          sections: [],
        ),
      );
      
      final courseInstructorSet = <String>{};
      for (final section in course.sections) {
        if (section.instructor.isNotEmpty) {
          // Split comma-separated instructors into individual instructors
          final instructorList = section.instructor.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
          for (final instructor in instructorList) {
            final instructorLower = instructor.toLowerCase();
            // Only add if we haven't seen this instructor name (case-insensitive) before
            if (!seenInstructorsLower.contains(instructorLower)) {
              seenInstructorsLower.add(instructorLower);
              courseInstructorSet.add(instructor);
            }
          }
        }
      }
      
      if (courseInstructorSet.isNotEmpty) {
        courseInstructors[courseCode] = courseInstructorSet.toList()..sort();
      }
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _InstructorAvoidanceDialog(
        courseInstructors: courseInstructors,
        currentlyAvoided: _avoidedInstructors,
      ),
    );
    
    if (result != null && mounted) {
      setState(() {
        for (final instructor in result) {
          if (!_avoidedInstructors.contains(instructor)) {
            _avoidedInstructors.add(instructor);
          }
        }
      });
    }
  }

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _selectedCourses.isNotEmpty && !_isGenerating
            ? LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _selectedCourses.isEmpty || _isGenerating
            ? Theme.of(context).colorScheme.surface
            : null,
      ),
      child: ElevatedButton(
        onPressed: _selectedCourses.isNotEmpty && !_isGenerating ? _generateTimetables : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isGenerating
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generating...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: _selectedCourses.isNotEmpty 
                        ? Theme.of(context).scaffoldBackgroundColor 
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Generate Timetables',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _selectedCourses.isNotEmpty 
                          ? Theme.of(context).scaffoldBackgroundColor 
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _generateTimetables() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final constraints = TimetableConstraints(
        requiredCourses: _selectedCourses,
        avoidTimes: _avoidTimes,
        avoidLabs: _avoidLabs,
        maxHoursPerDay: _maxHoursPerDay,
        preferredInstructors: _preferredInstructors,
        avoidedInstructors: _avoidedInstructors,
        avoidBackToBackClasses: _avoidBackToBack,
        preferredExamSlot: _preferredExamSlot,
      );

      final timetables = TimetableGenerator.generateTimetables(
        widget.availableCourses,
        constraints,
        maxTimetables: 30,
      );

      setState(() {
        _generatedTimetables = timetables;
        _isGenerating = false;
      });

      // Show alert if no timetables were generated
      if (timetables.isEmpty) {
        _showNoTimetablesDialog();
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      
      ToastService.showError('Error generating timetables: $e');
    }
  }

  Widget _buildGeneratedTimetables() {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Generated Timetables (${_generatedTimetables.length})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _generatedTimetables.length,
                itemBuilder: (context, index) {
                  final timetable = _generatedTimetables[index];
                  return GeneratedTimetableCard(
                    timetable: timetable,
                    onSelect: () => widget.onTimetableSelected(timetable.sections),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoTimetablesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('No Valid Timetables Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No conflict-free timetable combinations could be generated with your selected courses and constraints.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Try the following:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Remove some time constraints'),
            const Text('• Select fewer courses'),
            const Text('• Choose courses with more section options'),
            const Text('• Adjust your preferences'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All generated timetables are now conflict-free for better scheduling.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _TimeAvoidanceDialog extends StatefulWidget {
  const _TimeAvoidanceDialog();

  @override
  State<_TimeAvoidanceDialog> createState() => _TimeAvoidanceDialogState();
}

class _TimeAvoidanceDialogState extends State<_TimeAvoidanceDialog> {
  DayOfWeek? _selectedDay;
  final List<int> _selectedHours = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Time to Avoid'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              value: _selectedDay,
              items: DayOfWeek.values.map((day) => DropdownMenuItem(
                value: day,
                child: Text(day.name),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Hours to avoid:'),
            const SizedBox(height: 8),
            Container(
              height: 200,
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final hour = index + 1;
                  final isSelected = _selectedHours.contains(hour);
                  return FilterChip(
                    label: Text(
                      hour.toString(),
                      style: TextStyle(fontSize: 10),
                    ),
                    tooltip: TimeSlotInfo.getHourSlotName(hour),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedHours.add(hour);
                        } else {
                          _selectedHours.remove(hour);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedDay != null && _selectedHours.isNotEmpty
            ? () {
                final avoidTime = TimeAvoidance(
                  day: _selectedDay!,
                  hours: [..._selectedHours],
                );
                Navigator.pop(context, avoidTime);
              }
            : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LabAvoidanceDialog extends StatefulWidget {
  const _LabAvoidanceDialog();

  @override
  State<_LabAvoidanceDialog> createState() => _LabAvoidanceDialogState();
}

class _LabAvoidanceDialogState extends State<_LabAvoidanceDialog> {
  DayOfWeek? _selectedDay;
  final List<int> _selectedHours = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Lab Avoidance'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              value: _selectedDay,
              items: DayOfWeek.values.map((day) => DropdownMenuItem(
                value: day,
                child: Text(day.name),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Hours to avoid labs:'),
            const SizedBox(height: 8),
            Container(
              height: 200,
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final hour = index + 1;
                  final isSelected = _selectedHours.contains(hour);
                  return FilterChip(
                    label: Text(
                      hour.toString(),
                      style: TextStyle(fontSize: 10),
                    ),
                    tooltip: TimeSlotInfo.getHourSlotName(hour),
                    selected: isSelected,
                    selectedColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
                    checkmarkColor: Theme.of(context).colorScheme.error,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedHours.add(hour);
                        } else {
                          _selectedHours.remove(hour);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedDay != null && _selectedHours.isNotEmpty
            ? () {
                final avoidLab = LabAvoidance(
                  day: _selectedDay!,
                  hours: [..._selectedHours],
                );
                Navigator.pop(context, avoidLab);
              }
            : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _InstructorAvoidanceDialog extends StatefulWidget {
  final Map<String, List<String>> courseInstructors;
  final List<String> currentlyAvoided;

  const _InstructorAvoidanceDialog({
    required this.courseInstructors,
    required this.currentlyAvoided,
  });

  @override
  State<_InstructorAvoidanceDialog> createState() => _InstructorAvoidanceDialogState();
}

class _InstructorAvoidanceDialogState extends State<_InstructorAvoidanceDialog> {
  final List<String> _selectedInstructors = [];
  final Set<String> _expandedCourses = <String>{};

  @override
  void initState() {
    super.initState();
    // Expand all courses by default for better visibility
    _expandedCourses.addAll(widget.courseInstructors.keys);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Instructors to Avoid'),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentlyAvoided.isNotEmpty) ...[
              Text(
                'Currently avoiding: ${widget.currentlyAvoided.join(", ")}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Select instructors by course:'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.courseInstructors.isEmpty
                    ? const Center(
                        child: Text(
                          'No instructors found in selected courses',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.courseInstructors.keys.length,
                        itemBuilder: (context, index) {
                          final courseCode = widget.courseInstructors.keys.elementAt(index);
                          final instructors = widget.courseInstructors[courseCode]!;
                          final isExpanded = _expandedCourses.contains(courseCode);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    courseCode,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${instructors.length} instructor${instructors.length == 1 ? '' : 's'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedCourses.remove(courseCode);
                                      } else {
                                        _expandedCourses.add(courseCode);
                                      }
                                    });
                                  },
                                ),
                                if (isExpanded) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: instructors.map((instructor) {
                                        final isSelected = _selectedInstructors.contains(instructor);
                                        final isAlreadyAvoided = widget.currentlyAvoided.contains(instructor);
                                        
                                        return FilterChip(
                                          label: Text(
                                            instructor,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isAlreadyAvoided 
                                                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                                                  : null,
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
                                          checkmarkColor: Theme.of(context).colorScheme.error,
                                          backgroundColor: isAlreadyAvoided 
                                              ? Theme.of(context).colorScheme.surface.withOpacity(0.5)
                                              : null,
                                          onSelected: isAlreadyAvoided 
                                              ? null 
                                              : (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedInstructors.add(instructor);
                                                    } else {
                                                      _selectedInstructors.remove(instructor);
                                                    }
                                                  });
                                                },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_selectedInstructors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected to avoid (${_selectedInstructors.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedInstructors.join(", "),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedInstructors.isNotEmpty
              ? () => Navigator.pop(context, _selectedInstructors)
              : null,
          child: Text('Add ${_selectedInstructors.length} Instructor${_selectedInstructors.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}