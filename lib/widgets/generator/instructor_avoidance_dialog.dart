import 'package:flutter/material.dart';
import '../../services/ui/responsive_service.dart';

class InstructorAvoidanceDialog extends StatefulWidget {
  final Map<String, Map<String, List<String>>> courseSectionInstructors;
  final List<String> currentlyAvoided;

  const InstructorAvoidanceDialog({
    super.key,
    required this.courseSectionInstructors,
    required this.currentlyAvoided,
  });

  @override
  State<InstructorAvoidanceDialog> createState() => _InstructorAvoidanceDialogState();
}

class _InstructorAvoidanceDialogState extends State<InstructorAvoidanceDialog> {
  final List<String> _selectedInstructors = [];
  final Set<String> _expandedCourses = <String>{};

  @override
  void initState() {
    super.initState();
    _expandedCourses.addAll(widget.courseSectionInstructors.keys);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Instructors to Avoid'),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? double.infinity : 600,
        height: MediaQuery.of(context).size.height * 0.5,
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
                child: widget.courseSectionInstructors.isEmpty
                    ? const Center(
                        child: Text(
                          'No instructors found in selected courses',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.courseSectionInstructors.keys.length,
                        itemBuilder: (context, index) {
                          final courseCode = widget.courseSectionInstructors.keys.elementAt(index);
                          final sectionInstructors = widget.courseSectionInstructors[courseCode]!;
                          final isExpanded = _expandedCourses.contains(courseCode);

                          final totalInstructors = sectionInstructors.values
                              .expand((instructors) => instructors)
                              .toSet()
                              .length;

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
                                    '$totalInstructors instructor${totalInstructors == 1 ? '' : 's'} across ${sectionInstructors.keys.length} section type${sectionInstructors.keys.length == 1 ? '' : 's'}',
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: sectionInstructors.entries.map((sectionEntry) {
                                        final sectionType = sectionEntry.key;
                                        final instructors = sectionEntry.value;

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$sectionType (${instructors.length})',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: instructors.map((instructor) {
                                                  final sectionSpecificKey = '$courseCode-$sectionType-$instructor';
                                                  final isSelected = _selectedInstructors.contains(sectionSpecificKey);
                                                  final isAlreadyAvoided = widget.currentlyAvoided.contains(instructor);

                                                  return FilterChip(
                                                    label: Text(
                                                      instructor,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: isAlreadyAvoided
                                                            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
                                                            : null,
                                                      ),
                                                    ),
                                                    selected: isSelected,
                                                    selectedColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                                                    checkmarkColor: Theme.of(context).colorScheme.error,
                                                    backgroundColor: isAlreadyAvoided
                                                        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
                                                        : null,
                                                    onSelected: isAlreadyAvoided
                                                        ? null
                                                        : (selected) {
                                                            setState(() {
                                                              if (selected) {
                                                                _selectedInstructors.add(sectionSpecificKey);
                                                              } else {
                                                                _selectedInstructors.remove(sectionSpecificKey);
                                                              }
                                                            });
                                                          },
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                          ),
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
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
                      _selectedInstructors.map((key) {
                        final parts = key.split('-');
                        if (parts.length >= 3) {
                          final instructor = parts.sublist(2).join('-');
                          final courseCode = parts[0];
                          final sectionType = parts[1];
                          return '$instructor ($courseCode-$sectionType)';
                        }
                        return key;
                      }).join(", "),
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
        FilledButton(
          onPressed: _selectedInstructors.isNotEmpty
              ? () => Navigator.pop(context, _selectedInstructors)
              : null,
          child: Text('Add ${_selectedInstructors.length} Instructor${_selectedInstructors.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}
