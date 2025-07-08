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
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timetable Generator',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildCourseSelection(),
                const SizedBox(height: 16),
                _buildConstraints(),
                const SizedBox(height: 16),
                _buildGenerateButton(),
              ],
            ),
          ),
        ),
        if (_generatedTimetables.isNotEmpty) _buildGeneratedTimetables(),
      ],
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
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Text(
            'No courses selected',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
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
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    course.courseTitle,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedCourses.remove(courseCode);
                });
              },
              backgroundColor: Colors.blue.withOpacity(0.1),
              deleteIconColor: Colors.red,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildConstraints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constraints & Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Max hours per day:'),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: TextField(
                controller: TextEditingController(text: _maxHoursPerDay.toString()),
                keyboardType: TextInputType.number,
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
        const SizedBox(height: 8),
        CheckboxListTile(
          title: const Text('Avoid back-to-back classes'),
          value: _avoidBackToBack,
          onChanged: (value) {
            setState(() {
              _avoidBackToBack = value ?? false;
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Preferred exam slot:'),
            const SizedBox(width: 8),
            DropdownButton<TimeSlot?>(
              value: _preferredExamSlot,
              hint: const Text('Any'),
              items: [
                const DropdownMenuItem<TimeSlot?>(
                  value: null,
                  child: Text('Any'),
                ),
                ...TimeSlot.values.map((slot) => DropdownMenuItem(
                  value: slot,
                  child: Text(TimeSlotInfo.getTimeSlotName(slot)),
                )),
              ],
              onChanged: (value) {
                setState(() {
                  _preferredExamSlot = value;
                });
              },
            ),
          ],
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
            const Text('Avoid time slots:'),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addTimeAvoidance,
              child: const Text('Add'),
            ),
          ],
        ),
        if (_avoidTimes.isNotEmpty)
          ...(_avoidTimes.asMap().entries.map((entry) {
            final index = entry.key;
            final avoidTime = entry.value;
            return Chip(
              label: Text('${avoidTime.day.name}: ${_formatAvoidTimeHours(avoidTime.hours)}'),
              onDeleted: () {
                setState(() {
                  _avoidTimes.removeAt(index);
                });
              },
            );
          })),
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
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
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
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _selectedCourses.isNotEmpty && !_isGenerating ? _generateTimetables : null,
        child: _isGenerating
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Generating...'),
              ],
            )
          : const Text('Generate Timetables'),
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