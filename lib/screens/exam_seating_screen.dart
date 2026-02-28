import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/exam_seating_service.dart';
import '../services/timetable_service.dart';
import '../services/responsive_service.dart';
import '../services/toast_service.dart';
import '../models/timetable.dart';
import '../widgets/app_drawer.dart';

class ExamSeatingScreen extends StatefulWidget {
  const ExamSeatingScreen({super.key});

  @override
  State<ExamSeatingScreen> createState() => _ExamSeatingScreenState();
}

class _ExamSeatingScreenState extends State<ExamSeatingScreen> {
  final ExamSeatingService _examSeatingService = ExamSeatingService();
  final TimetableService _timetableService = TimetableService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _idController = TextEditingController();

  List<ExamSeating> _allExams = [];
  List<ExamSeating> _selectedCourses = [];
  Map<String, ExamRoom?> _searchResults = {};
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExamData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _loadExamData() async {
    setState(() => _isLoading = true);
    final exams = await _examSeatingService.fetchAllExamSeating();

    // Load saved user data
    final savedData = await _examSeatingService.loadUserData();

    setState(() {
      _allExams = exams;
      _isLoading = false;

      // Restore saved courses and student ID
      if (savedData != null) {
        _idController.text = savedData.studentId;

        // Find matching exams for saved course codes
        for (final courseCode in savedData.selectedCourseCodes) {
          final exam = exams.firstWhere(
            (e) => e.courseCode.replaceAll(' ', '').toUpperCase() ==
                courseCode.replaceAll(' ', '').toUpperCase(),
            orElse: () => ExamSeating(
              courseCode: courseCode,
              courseTitle: '',
              examDate: '',
              rooms: [],
            ),
          );
          if (exam.rooms.isNotEmpty &&
              !_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
            _selectedCourses.add(exam);
          }
        }
      }
    });
  }

  Future<void> _importCoursesFromTimetable() async {
    try {
      final allTimetables = await _timetableService.getAllTimetables();

      if (allTimetables.isEmpty) {
        ToastService.showError(
          'No timetables found. Please create a timetable first.',
        );
        return;
      }

      if (!mounted) return;

      final selectedCourses = await showDialog<List<String>>(
        context: context,
        builder: (context) => _TimetableCourseSelectionDialog(
          timetables: allTimetables,
          allExams: _allExams,
        ),
      );

      if (selectedCourses == null || selectedCourses.isEmpty) {
        return;
      }

      // Find exam seating data for selected courses
      final coursesToAdd = <ExamSeating>[];
      for (final courseCode in selectedCourses) {
        final exam = _allExams.firstWhere(
          (e) =>
              e.courseCode.replaceAll(' ', '').toUpperCase() ==
              courseCode.replaceAll(' ', '').toUpperCase(),
          orElse: () => ExamSeating(
            courseCode: courseCode,
            courseTitle: '',
            examDate: '',
            rooms: [],
          ),
        );
        if (exam.rooms.isNotEmpty &&
            !_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
          coursesToAdd.add(exam);
        }
      }

      if (coursesToAdd.isEmpty) {
        ToastService.showInfo(
          'No exam seating data found for the selected courses.',
        );
        return;
      }

      setState(() {
        _selectedCourses.addAll(coursesToAdd);
      });

      ToastService.showSuccess(
        'Added ${coursesToAdd.length} course${coursesToAdd.length != 1 ? 's' : ''}!',
      );
    } catch (e) {
      ToastService.showError('Error importing courses: $e');
    }
  }

  void _addCourse(ExamSeating exam) {
    if (_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
      ToastService.showInfo('Course already added');
      return;
    }

    setState(() {
      _selectedCourses.add(exam);
      _searchController.clear();
    });
  }

  void _removeCourse(ExamSeating exam) {
    setState(() {
      _selectedCourses.removeWhere((c) => c.courseCode == exam.courseCode);
      _searchResults.remove(exam.courseCode);
    });
  }

  void _searchForRoom() {
    final studentId = _idController.text.trim();
    if (studentId.isEmpty) {
      ToastService.showError('Please enter your ID number');
      return;
    }

    if (_selectedCourses.isEmpty) {
      ToastService.showError('Please add at least one course');
      return;
    }

    setState(() => _isSearching = true);

    final results = <String, ExamRoom?>{};
    for (final course in _selectedCourses) {
      results[course.courseCode] = course.findRoomForStudent(studentId);
    }

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _saveUserData() async {
    if (_selectedCourses.isEmpty && _idController.text.trim().isEmpty) {
      ToastService.showInfo('Nothing to save');
      return;
    }

    setState(() => _isSaving = true);

    final success = await _examSeatingService.saveUserData(
      selectedCourseCodes: _selectedCourses.map((c) => c.courseCode).toList(),
      studentId: _idController.text.trim(),
    );

    setState(() => _isSaving = false);

    if (success) {
      ToastService.showSuccess('Saved successfully!');
    } else {
      ToastService.showError('Please sign in to save your data');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Exam Seating'),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(currentScreen: DrawerScreen.examSeating),
      appBar: AppBar(
        title: const Text('Exam Seating'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import Courses from Timetable',
            onPressed: _importCoursesFromTimetable,
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            tooltip: 'Save',
            onPressed: _isSaving ? null : _saveUserData,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Data',
            onPressed: _loadExamData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchSection(),
          Expanded(child: _buildSelectedCourses()),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Course search
          TypeAheadField<ExamSeating>(
            controller: _searchController,
            suggestionsCallback: (pattern) async {
              if (pattern.isEmpty) return [];
              return _allExams
                  .where((exam) =>
                      exam.courseCode
                          .toUpperCase()
                          .contains(pattern.toUpperCase()) ||
                      exam.courseTitle
                          .toUpperCase()
                          .contains(pattern.toUpperCase()))
                  .take(10)
                  .toList();
            },
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Search for a course...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              );
            },
            itemBuilder: (context, exam) {
              return ListTile(
                title: Text(exam.courseCode),
                subtitle: Text(
                  exam.courseTitle.isNotEmpty
                      ? exam.courseTitle
                      : 'No title available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: exam.examDate.isNotEmpty
                    ? Text(
                        exam.examDate,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : null,
              );
            },
            onSelected: _addCourse,
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No courses found'),
            ),
          ),

          const SizedBox(height: 16),

          // ID Number input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _idController,
                  decoration: InputDecoration(
                    hintText: 'Enter your ID Number (e.g., 2022A7PS0001H)',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _searchForRoom(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isSearching ? null : _searchForRoom,
                icon: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Find Room'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compare two exam date strings for sorting
  /// Expected format: "DD/MM/YYYY AN/FN" or similar
  int _compareExamDates(String dateA, String dateB) {
    if (dateA.isEmpty && dateB.isEmpty) return 0;
    if (dateA.isEmpty) return 1; // Empty dates go to end
    if (dateB.isEmpty) return -1;

    try {
      // Parse date and time from strings like "03/12/2024 AN" or "03/12/2024 FN"
      final parsedA = _parseExamDateTime(dateA);
      final parsedB = _parseExamDateTime(dateB);

      if (parsedA == null && parsedB == null) return dateA.compareTo(dateB);
      if (parsedA == null) return 1;
      if (parsedB == null) return -1;

      return parsedA.compareTo(parsedB);
    } catch (e) {
      // Fallback to string comparison
      return dateA.compareTo(dateB);
    }
  }

  /// Parse exam date string to DateTime for comparison
  /// Handles formats like:
  /// - "03/12/2024 AN", "03/12/2024 FN", "3/12/2024"
  /// - "09 March 26 - 04:00 PM to 05:30 PM"
  /// - "09 March 26 - 09:30 AM to 11:00 AM"
  DateTime? _parseExamDateTime(String dateStr) {
    try {
      final normalized = dateStr.trim();

      // Try format: "DD Month YY - HH:MM AM/PM to HH:MM AM/PM"
      // Example: "09 March 26 - 04:00 PM to 05:30 PM"
      final monthNames = {
        'JANUARY': 1, 'JAN': 1,
        'FEBRUARY': 2, 'FEB': 2,
        'MARCH': 3, 'MAR': 3,
        'APRIL': 4, 'APR': 4,
        'MAY': 5,
        'JUNE': 6, 'JUN': 6,
        'JULY': 7, 'JUL': 7,
        'AUGUST': 8, 'AUG': 8,
        'SEPTEMBER': 9, 'SEP': 9,
        'OCTOBER': 10, 'OCT': 10,
        'NOVEMBER': 11, 'NOV': 11,
        'DECEMBER': 12, 'DEC': 12,
      };

      // Pattern: DD Month YY - HH:MM AM/PM
      final newFormatRegex = RegExp(
        r'(\d{1,2})\s+(\w+)\s+(\d{2,4})\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)',
        caseSensitive: false,
      );
      final newMatch = newFormatRegex.firstMatch(normalized);
      if (newMatch != null) {
        final day = int.tryParse(newMatch.group(1)!);
        final monthStr = newMatch.group(2)!.toUpperCase();
        var year = int.tryParse(newMatch.group(3)!);
        var hour = int.tryParse(newMatch.group(4)!);
        final minute = int.tryParse(newMatch.group(5)!);
        final ampm = newMatch.group(6)!.toUpperCase();
        final month = monthNames[monthStr];

        if (day != null && month != null && year != null && hour != null && minute != null) {
          // Handle 2-digit year
          if (year < 100) {
            year += 2000;
          }
          // Convert to 24-hour format
          if (ampm == 'PM' && hour != 12) {
            hour += 12;
          } else if (ampm == 'AM' && hour == 12) {
            hour = 0;
          }
          return DateTime(year, month, day, hour, minute);
        }
      }

      // Fallback: Try DD/MM/YYYY AN/FN format
      final upperNormalized = normalized.toUpperCase();
      final isAfternoon = upperNormalized.contains('FN');

      // Extract date part (remove AN/FN)
      final datePart = upperNormalized
          .replaceAll('AN', '')
          .replaceAll('FN', '')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .trim();

      // Try DD/MM/YYYY format
      final parts = datePart.split('/');
      if (parts.length >= 3) {
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);

        if (day != null && month != null && year != null) {
          // AN = 9:00 AM, FN = 2:00 PM
          final hour = isAfternoon ? 14 : 9;
          return DateTime(year, month, day, hour);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Widget _buildSelectedCourses() {
    if (_selectedCourses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_seat_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No courses selected',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Search for a course above or import from your timetable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // Sort courses by exam date
    final sortedCourses = List<ExamSeating>.from(_selectedCourses)
      ..sort((a, b) => _compareExamDates(a.examDate, b.examDate));

    return ListView.builder(
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      itemCount: sortedCourses.length,
      itemBuilder: (context, index) {
        final course = sortedCourses[index];
        final room = _searchResults[course.courseCode];
        final hasSearched = _searchResults.containsKey(course.courseCode);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.courseCode,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (course.courseTitle.isNotEmpty)
                            Text(
                              course.courseTitle,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (course.examDate.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.event,
                                    size: 16,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    course.examDate,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _removeCourse(course),
                      tooltip: 'Remove course',
                    ),
                  ],
                ),

                // Show room result if searched
                if (hasSearched) ...[
                  const Divider(height: 24),
                  if (room != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Room: ${room.roomNo}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[700],
                                      ),
                                ),
                                Text(
                                  'ID Range: ${room.idFrom} - ${room.idTo}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.green[700],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No room found for your ID in this course',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.orange[700],
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dialog for selecting courses from timetables
class _TimetableCourseSelectionDialog extends StatefulWidget {
  final List<Timetable> timetables;
  final List<ExamSeating> allExams;

  const _TimetableCourseSelectionDialog({
    required this.timetables,
    required this.allExams,
  });

  @override
  State<_TimetableCourseSelectionDialog> createState() =>
      _TimetableCourseSelectionDialogState();
}

class _TimetableCourseSelectionDialogState
    extends State<_TimetableCourseSelectionDialog> {
  Timetable? _selectedTimetable;
  final Set<String> _selectedCourses = {};

  @override
  void initState() {
    super.initState();
    if (widget.timetables.isNotEmpty) {
      _selectedTimetable = widget.timetables.first;
    }
  }

  List<String> get _availableCourses {
    if (_selectedTimetable == null) return [];

    // Get unique course codes from selectedSections (courses actually in the timetable)
    final courseCodes = <String>{};
    for (final selectedSection in _selectedTimetable!.selectedSections) {
      courseCodes.add(selectedSection.courseCode);
    }

    // Filter to only courses that have exam seating data
    return courseCodes.where((code) {
      return widget.allExams.any((exam) =>
          exam.courseCode.replaceAll(' ', '').toUpperCase() ==
          code.replaceAll(' ', '').toUpperCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Courses'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timetable selector
            DropdownButtonFormField<Timetable>(
              value: _selectedTimetable,
              decoration: const InputDecoration(
                labelText: 'Select Timetable',
                border: OutlineInputBorder(),
              ),
              items: widget.timetables
                  .map((tt) => DropdownMenuItem(
                        value: tt,
                        child: Text(tt.name),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTimetable = value;
                  _selectedCourses.clear();
                });
              },
            ),
            const SizedBox(height: 16),

            // Course list
            if (_availableCourses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No courses with exam seating data found in this timetable.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableCourses.length,
                  itemBuilder: (context, index) {
                    final courseCode = _availableCourses[index];
                    final isSelected = _selectedCourses.contains(courseCode);

                    return CheckboxListTile(
                      title: Text(courseCode),
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
        FilledButton(
          onPressed: _selectedCourses.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedCourses.toList()),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
