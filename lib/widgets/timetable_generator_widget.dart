import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../services/timetable_generator.dart';
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
  int _maxHoursPerDay = 8;
  final List<String> _preferredInstructors = [];
  final List<String> _avoidedInstructors = [];
  bool _avoidBackToBack = false;
  TimeSlot? _preferredExamSlot;
  List<GeneratedTimetable> _generatedTimetables = [];
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF21262D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: const Color(0xFF58A6FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Course Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0F6FC),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF21262D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: const Color(0xFF58A6FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Constraints & Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0F6FC),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF21262D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.view_list,
                  color: const Color(0xFF58A6FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Generated Timetables',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0F6FC),
                  ),
                ),
                const Spacer(),
                if (_generatedTimetables.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF58A6FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_generatedTimetables.length} found',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF58A6FF),
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
            color: const Color(0xFF8B949E),
          ),
          const SizedBox(height: 16),
          Text(
            _isGenerating ? 'Generating timetables...' : 'No timetables generated yet',
            style: const TextStyle(
              color: Color(0xFFF0F6FC),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isGenerating 
                ? 'This may take a few moments'
                : 'Select courses and click Generate to see results',
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 14,
            ),
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(
              color: Color(0xFF58A6FF),
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
          color: const Color(0xFF21262D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: const Center(
          child: Text(
            'No courses selected',
            style: TextStyle(
              color: Color(0xFF8B949E),
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
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8B949E),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF21262D).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Color(0xFF58A6FF),
                    ),
                  ),
                  Text(
                    course.courseTitle,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF8B949E),
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
              backgroundColor: const Color(0xFF58A6FF).withOpacity(0.1),
              deleteIconColor: const Color(0xFFFF6B6B),
              side: BorderSide(
                color: const Color(0xFF58A6FF).withOpacity(0.3),
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
            color: const Color(0xFF21262D).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
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
                  style: const TextStyle(fontSize: 14),
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
            color: const Color(0xFF21262D).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
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
            color: const Color(0xFF21262D).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
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
                        style: const TextStyle(fontSize: 14),
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
        const SizedBox(height: 8),
        _buildTimeAvoidance(),
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
              color: const Color(0xFF21262D).withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
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
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _avoidTimes.removeAt(index);
                      });
                    },
                    backgroundColor: const Color(0xFF58A6FF).withOpacity(0.1),
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
    // Get all unique instructors from selected courses
    final Set<String> availableInstructors = <String>{};
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
      for (final section in course.sections) {
        if (section.instructor.isNotEmpty) {
          availableInstructors.add(section.instructor);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Avoid Instructors:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (availableInstructors.isNotEmpty) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 100),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D).withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: availableInstructors.map((instructor) {
                  final isAvoided = _avoidedInstructors.contains(instructor);
                  return FilterChip(
                    label: Text(
                      instructor,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: isAvoided,
                    selectedColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
                    checkmarkColor: Theme.of(context).colorScheme.error,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _avoidedInstructors.add(instructor);
                        } else {
                          _avoidedInstructors.remove(instructor);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
            ),
            child: const Text(
              'Select courses first to see available instructors',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (_avoidedInstructors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Avoiding: ${_avoidedInstructors.join(", ")}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w500,
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

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _selectedCourses.isNotEmpty && !_isGenerating
            ? const LinearGradient(
                colors: [Color(0xFF58A6FF), Color(0xFF79C0FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _selectedCourses.isEmpty || _isGenerating
            ? const Color(0xFF21262D)
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
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF58A6FF),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generating...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF58A6FF),
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
                        ? const Color(0xFF0D1117) 
                        : const Color(0xFF8B949E),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Generate Timetables',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _selectedCourses.isNotEmpty 
                          ? const Color(0xFF0D1117) 
                          : const Color(0xFF8B949E),
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
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating timetables: $e')),
      );
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      style: const TextStyle(fontSize: 10),
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