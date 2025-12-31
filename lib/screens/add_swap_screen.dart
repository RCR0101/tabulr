import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_data_service.dart';
import '../services/responsive_service.dart';
import '../widgets/search_filter_widget.dart';

class AddSwapScreen extends StatefulWidget {
  final List<SelectedSection> currentSelectedSections;
  final List<Course> availableCourses;
  final String currentCampus;
  final Function(List<SelectedSection>)? onTimetableUpdated;

  const AddSwapScreen({
    super.key,
    required this.currentSelectedSections,
    required this.availableCourses,
    required this.currentCampus,
    this.onTimetableUpdated,
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
  List<SafeCourseResult> _safeCourseResults = [];
  List<SafeCourseResult> _filteredSafeCourseResults = [];
  List<SelectedSection> _currentTimetableSections = [];
  bool _isLoading = true;
  bool _isValidating = false;
  bool _isCheckingAll = false;
  String _searchQuery = '';
  String _safeCourseSearchQuery = '';
  String? _selectedDiscipline;
  String? _selectedLevel;

  @override
  void initState() {
    super.initState();
    _currentTimetableSections = List.from(widget.currentSelectedSections);
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

    // Check for incomplete course selections
    final incompleteSelections = <String>[];
    for (final entry in _selectedSections.entries) {
      final courseCode = entry.key;
      final selectedSectionTypes = entry.value.keys.toSet();
      
      // Find all available section types for this course
      final course = _availableCourses.firstWhere((c) => c.courseCode == courseCode);
      final availableSectionTypes = course.sections.map((s) => s.type).toSet();
      
      // Check if user has selected from all available types
      final missingSectionTypes = availableSectionTypes.difference(selectedSectionTypes);
      if (missingSectionTypes.isNotEmpty) {
        final missingTypeNames = missingSectionTypes.map((t) => _getSectionTypeName(t)).join(', ');
        incompleteSelections.add('$courseCode: Missing $missingTypeNames');
      }
    }

    if (incompleteSelections.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Incomplete Course Selection'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please select sections from all available types for the following courses:'),
                const SizedBox(height: 12),
                ...incompleteSelections.map((incomplete) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning, color: Theme.of(context).colorScheme.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(incomplete, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _validationResults = [];
    });

    try {
      final List<ValidationResult> results = [];
      
      // Create a list of all newly selected sections for cross-checking
      final List<SelectedSection> newlySelectedSections = [];
      for (final entry in _selectedSections.entries) {
        final courseCode = entry.key;
        final sectionsByType = entry.value;
        final course = _availableCourses.firstWhere((c) => c.courseCode == courseCode);
        
        for (final typeEntry in sectionsByType.entries) {
          final sectionType = typeEntry.key;
          final sectionId = typeEntry.value;
          final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
          
          newlySelectedSections.add(SelectedSection(
            courseCode: courseCode,
            sectionId: sectionId,
            section: section,
          ));
        }
      }
      
      for (final entry in _selectedSections.entries) {
        final courseCode = entry.key;
        final sectionsByType = entry.value;
        
        final course = _availableCourses.firstWhere((c) => c.courseCode == courseCode);
        
        for (final typeEntry in sectionsByType.entries) {
          final sectionType = typeEntry.key;
          final sectionId = typeEntry.value;
          
          final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
          
          final conflicts = _checkForConflicts(section);
          final examConflicts = _checkForExamConflicts(course);
          final newSelectionConflicts = _checkForNewSelectionConflicts(section, course, courseCode, sectionId, newlySelectedSections);
          final allConflicts = [...conflicts, ...examConflicts, ...newSelectionConflicts];
          
          results.add(ValidationResult(
            courseCode: courseCode,
            sectionId: sectionId,
            sectionType: sectionType,
            courseTitle: course.courseTitle,
            canBeAdded: allConflicts.isEmpty,
            conflicts: allConflicts,
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
      _safeCourseResults.clear();
      _filteredSafeCourseResults.clear();
      _safeCourseSearchQuery = '';
    });
  }

  void _filterSafeCourseResults() {
    setState(() {
      _filteredSafeCourseResults = _safeCourseResults.where((result) {
        return _safeCourseSearchQuery.isEmpty ||
            result.courseCode.toLowerCase().contains(_safeCourseSearchQuery.toLowerCase()) ||
            result.courseTitle.toLowerCase().contains(_safeCourseSearchQuery.toLowerCase()) ||
            result.instructors.any((instructor) =>
                instructor.toLowerCase().contains(_safeCourseSearchQuery.toLowerCase()));
      }).toList();
    });
  }

  List<ConflictInfo> _checkForConflicts(Section section) {
    final conflicts = <ConflictInfo>[];
    
    for (final scheduleEntry in section.schedule) {
      for (final day in scheduleEntry.days) {
        for (final hour in scheduleEntry.hours) {
          for (final currentSelected in _currentTimetableSections) {
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

  List<ConflictInfo> _checkForExamConflicts(Course newCourse) {
    final conflicts = <ConflictInfo>[];
    
    // Check for mid-semester exam conflicts
    if (newCourse.midSemExam != null) {
      for (final currentSelected in _currentTimetableSections) {
        final currentCourse = _availableCourses.firstWhere(
          (c) => c.courseCode == currentSelected.courseCode,
        );
        
        if (currentCourse.midSemExam != null) {
          // Check if exams are on the same date and have overlapping time slots
          if (_examDatesConflict(newCourse.midSemExam!, currentCourse.midSemExam!)) {
            conflicts.add(ConflictInfo(
              conflictingCourse: currentSelected.courseCode,
              conflictingSectionId: 'Mid-Sem Exam',
              day: DayOfWeek.M, // Placeholder, exams don't follow day structure
              time: 'Mid-Sem Exam: ${TimeSlotInfo.getTimeSlotName(newCourse.midSemExam!.timeSlot)}',
            ));
          }
        }
      }
    }
    
    // Check for comprehensive exam conflicts
    if (newCourse.endSemExam != null) {
      for (final currentSelected in _currentTimetableSections) {
        final currentCourse = _availableCourses.firstWhere(
          (c) => c.courseCode == currentSelected.courseCode,
        );
        
        if (currentCourse.endSemExam != null) {
          // Check if exams are on the same date and have overlapping time slots
          if (_examDatesConflict(newCourse.endSemExam!, currentCourse.endSemExam!)) {
            conflicts.add(ConflictInfo(
              conflictingCourse: currentSelected.courseCode,
              conflictingSectionId: 'Comprehensive Exam',
              day: DayOfWeek.M, // Placeholder, exams don't follow day structure
              time: 'Comprehensive Exam: ${TimeSlotInfo.getTimeSlotName(newCourse.endSemExam!.timeSlot)}',
            ));
          }
        }
      }
    }
    
    return conflicts;
  }

  bool _examDatesConflict(ExamSchedule exam1, ExamSchedule exam2) {
    // Check if exams are on the same date
    if (exam1.date.year == exam2.date.year &&
        exam1.date.month == exam2.date.month &&
        exam1.date.day == exam2.date.day) {
      
      // Check if time slots overlap
      return _examTimeSlotsOverlap(exam1.timeSlot, exam2.timeSlot);
    }
    return false;
  }

  bool _examTimeSlotsOverlap(TimeSlot slot1, TimeSlot slot2) {
    // If they're the exact same slot, they definitely overlap
    if (slot1 == slot2) return true;
    
    // Check for overlapping time ranges
    // Note: This is a simplified check. In practice, you might want more sophisticated logic
    // based on the actual times defined in TimeSlotInfo.timeSlotNames
    
    // For mid-semester exams (MS1-MS4), check for overlaps
    final midSemSlots = [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4];
    if (midSemSlots.contains(slot1) && midSemSlots.contains(slot2)) {
      // MS1: 9:30-11:00, MS2: 11:30-1:00, MS3: 1:30-3:00, MS4: 3:30-5:00
      // These don't overlap as they have 30-minute gaps
      return false;
    }
    
    // For comprehensive exams (FN, AN), check for overlaps
    final compSlots = [TimeSlot.FN, TimeSlot.AN];
    if (compSlots.contains(slot1) && compSlots.contains(slot2)) {
      // FN: 8:00AM-11:00AM, AN: 3:00PM-6:00PM
      // These don't overlap
      return false;
    }
    
    // No overlap between different exam types (mid-sem vs comprehensive)
    return false;
  }

  List<ConflictInfo> _checkForNewSelectionConflicts(
    Section currentSection, 
    Course currentCourse, 
    String currentCourseCode, 
    String currentSectionId, 
    List<SelectedSection> allNewlySelected
  ) {
    final conflicts = <ConflictInfo>[];
    
    // Check class schedule conflicts with other newly selected sections
    for (final scheduleEntry in currentSection.schedule) {
      for (final day in scheduleEntry.days) {
        for (final hour in scheduleEntry.hours) {
          for (final otherSelected in allNewlySelected) {
            // Skip checking against itself
            if (otherSelected.courseCode == currentCourseCode && otherSelected.sectionId == currentSectionId) {
              continue;
            }
            
            for (final otherScheduleEntry in otherSelected.section.schedule) {
              if (otherScheduleEntry.days.contains(day) && otherScheduleEntry.hours.contains(hour)) {
                conflicts.add(ConflictInfo(
                  conflictingCourse: otherSelected.courseCode,
                  conflictingSectionId: otherSelected.sectionId,
                  day: day,
                  time: TimeSlotInfo.getHourSlotName(hour),
                ));
              }
            }
          }
        }
      }
    }
    
    // Check exam conflicts with other newly selected courses
    final examConflicts = _checkForExamConflictsBetweenNewSelections(currentCourse, currentCourseCode, allNewlySelected);
    conflicts.addAll(examConflicts);
    
    return conflicts;
  }

  List<ConflictInfo> _checkForExamConflictsBetweenNewSelections(
    Course currentCourse, 
    String currentCourseCode, 
    List<SelectedSection> allNewlySelected
  ) {
    final conflicts = <ConflictInfo>[];
    
    // Get unique courses from newly selected sections
    final Set<String> otherCourseCodes = allNewlySelected
        .map((s) => s.courseCode)
        .where((code) => code != currentCourseCode)
        .toSet();
    
    for (final otherCourseCode in otherCourseCodes) {
      final otherCourse = _availableCourses.firstWhere((c) => c.courseCode == otherCourseCode);
      
      // Check mid-semester exam conflicts
      if (currentCourse.midSemExam != null && otherCourse.midSemExam != null) {
        if (_examDatesConflict(currentCourse.midSemExam!, otherCourse.midSemExam!)) {
          conflicts.add(ConflictInfo(
            conflictingCourse: otherCourseCode,
            conflictingSectionId: 'Mid-Sem Exam',
            day: DayOfWeek.M, // Placeholder
            time: 'Mid-Sem Exam: ${TimeSlotInfo.getTimeSlotName(currentCourse.midSemExam!.timeSlot)}',
          ));
        }
      }
      
      // Check comprehensive exam conflicts
      if (currentCourse.endSemExam != null && otherCourse.endSemExam != null) {
        if (_examDatesConflict(currentCourse.endSemExam!, otherCourse.endSemExam!)) {
          conflicts.add(ConflictInfo(
            conflictingCourse: otherCourseCode,
            conflictingSectionId: 'Comprehensive Exam',
            day: DayOfWeek.M, // Placeholder
            time: 'Comprehensive Exam: ${TimeSlotInfo.getTimeSlotName(currentCourse.endSemExam!.timeSlot)}',
          ));
        }
      }
    }
    
    return conflicts;
  }

  Future<void> _checkAllCourses() async {
    setState(() {
      _isCheckingAll = true;
      _safeCourseResults.clear();
      _validationResults.clear();
    });

    try {
      final List<SafeCourseResult> safeCourses = [];
      
      for (final course in _availableCourses) {
        final safeCombination = _findSafeCombination(course);
        if (safeCombination != null) {
          // Get additional info for display
          final List<String> instructors = [];
          final List<String> rooms = [];
          final List<String> scheduleEntries = [];
          
          for (final entry in safeCombination.entries) {
            final sectionType = entry.key;
            final sectionId = entry.value;
            final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
            
            if (section.instructor.isNotEmpty && !instructors.contains(section.instructor)) {
              instructors.add(section.instructor);
            }
            if (section.room.isNotEmpty && !rooms.contains(section.room)) {
              rooms.add(section.room);
            }
            
            for (final scheduleEntry in section.schedule) {
              final days = scheduleEntry.days.map(_getDayName).join('/');
              final hours = scheduleEntry.hours.map((h) => TimeSlotInfo.getHourSlotName(h)).join(', ');
              scheduleEntries.add('${_getSectionTypeName(sectionType)}: $days: $hours');
            }
          }
          
          safeCourses.add(SafeCourseResult(
            courseCode: course.courseCode,
            courseTitle: course.courseTitle,
            safeCombination: safeCombination,
            instructors: instructors,
            rooms: rooms,
            scheduleDescription: scheduleEntries.join(' | '),
            course: course,
          ));
        }
      }
      
      setState(() {
        _safeCourseResults = safeCourses;
        _filteredSafeCourseResults = safeCourses;
        _isCheckingAll = false;
      });

      if (safeCourses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No courses found that can be safely added without conflicts')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isCheckingAll = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking courses: $e')),
        );
      }
    }
  }

  Map<SectionType, String>? _findSafeCombination(Course course) {
    // Group sections by type
    final Map<SectionType, List<Section>> sectionsByType = {};
    for (final section in course.sections) {
      sectionsByType.putIfAbsent(section.type, () => []).add(section);
    }
    
    // Get all required section types (ignore T and P if they don't exist)
    final requiredTypes = sectionsByType.keys.toSet();
    
    // Generate all possible combinations
    final combinations = _generateCombinations(sectionsByType, requiredTypes.toList());
    
    // Check each combination for conflicts
    for (final combination in combinations) {
      if (_isCombinationSafe(course, combination)) {
        return combination;
      }
    }
    
    return null;
  }

  List<Map<SectionType, String>> _generateCombinations(
    Map<SectionType, List<Section>> sectionsByType, 
    List<SectionType> types
  ) {
    if (types.isEmpty) return [{}];
    
    final currentType = types.first;
    final remainingTypes = types.sublist(1);
    final sectionsForType = sectionsByType[currentType] ?? [];
    
    final subCombinations = _generateCombinations(sectionsByType, remainingTypes);
    final allCombinations = <Map<SectionType, String>>[];
    
    for (final section in sectionsForType) {
      for (final subCombination in subCombinations) {
        final newCombination = Map<SectionType, String>.from(subCombination);
        newCombination[currentType] = section.sectionId;
        allCombinations.add(newCombination);
      }
    }
    
    return allCombinations;
  }

  bool _isCombinationSafe(Course course, Map<SectionType, String> combination) {
    // Check for conflicts with existing selected sections
    for (final entry in combination.entries) {
      final sectionType = entry.key;
      final sectionId = entry.value;
      final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
      
      // Check class schedule conflicts with current timetable
      final classConflicts = _checkForConflicts(section);
      if (classConflicts.isNotEmpty) return false;
    }
    
    // Check exam conflicts with current timetable
    final examConflicts = _checkForExamConflicts(course);
    if (examConflicts.isNotEmpty) return false;
    
    // Check for internal conflicts within the combination
    final sectionsInCombination = combination.entries.map((entry) {
      final sectionId = entry.value;
      return course.sections.firstWhere((s) => s.sectionId == sectionId);
    }).toList();
    
    for (int i = 0; i < sectionsInCombination.length; i++) {
      for (int j = i + 1; j < sectionsInCombination.length; j++) {
        if (_sectionsConflict(sectionsInCombination[i], sectionsInCombination[j])) {
          return false;
        }
      }
    }
    
    return true;
  }

  bool _sectionsConflict(Section section1, Section section2) {
    for (final schedule1 in section1.schedule) {
      for (final schedule2 in section2.schedule) {
        // Check for day and time overlaps
        for (final day1 in schedule1.days) {
          if (schedule2.days.contains(day1)) {
            for (final hour1 in schedule1.hours) {
              if (schedule2.hours.contains(hour1)) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add/Swap Courses'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isMobile
              ? _buildMobileLayout()
              : _buildDesktopLayout(),
    );
  }
  
  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.schedule, size: ResponsiveService.getAdaptiveIconSize(context, 20)),
                text: 'Current',
              ),
              Tab(
                icon: Icon(Icons.add_circle_outline, size: ResponsiveService.getAdaptiveIconSize(context, 20)),
                text: 'Add/Swap',
              ),
            ],
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCurrentCoursesSection(),
                _buildNewCoursesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDesktopLayout() {
    return Row(
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
    );
  }

  Widget _buildCurrentCoursesSection() {
    // Group selected sections by course code
    final currentCourses = <String, List<SelectedSection>>{};
    for (final selectedSection in _currentTimetableSections) {
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
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    ResponsiveService.isMobile(context) ? 100 : 16,
                  ),
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
                            // Show exam information if available
                            if (course.midSemExam != null || course.endSemExam != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_outlined,
                                          size: 14,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Exams',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (course.midSemExam != null) ...[
                                      _buildCompactExamInfo('Mid-Sem', course.midSemExam!),
                                      if (course.endSemExam != null) const SizedBox(height: 3),
                                    ],
                                    if (course.endSemExam != null)
                                      _buildCompactExamInfo('Comprehensive', course.endSemExam!),
                                  ],
                                ),
                              ),
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
              // Check All button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingAll ? null : () {
                    ResponsiveService.triggerMediumFeedback(context);
                    _checkAllCourses();
                  },
                  icon: _isCheckingAll
                      ? SizedBox(
                          width: ResponsiveService.getAdaptiveIconSize(context, 16),
                          height: ResponsiveService.getAdaptiveIconSize(context, 16),
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.checklist, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                  label: Text(_isCheckingAll ? 'Checking All Courses...' : 'Check All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    minimumSize: Size(
                      double.infinity,
                      ResponsiveService.getTouchTargetSize(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Action buttons - responsive layout
              ResponsiveService.buildResponsive(
                context,
                mobile: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _selectedSections.isEmpty ? null : () {
                          ResponsiveService.triggerSelectionFeedback(context);
                          _clearSelection();
                        },
                        icon: Icon(Icons.clear, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                        label: const Text('Clear Selection'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(
                            double.infinity,
                            ResponsiveService.getTouchTargetSize(context),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isValidating ? null : () {
                          ResponsiveService.triggerMediumFeedback(context);
                          _validateSelection();
                        },
                        icon: _isValidating
                            ? SizedBox(
                                width: ResponsiveService.getAdaptiveIconSize(context, 16),
                                height: ResponsiveService.getAdaptiveIconSize(context, 16),
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.verified_user, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                        label: Text(_isValidating ? 'Validating...' : 'Validate Selection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          minimumSize: Size(
                            double.infinity,
                            ResponsiveService.getTouchTargetSize(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                tablet: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectedSections.isEmpty ? null : () {
                          ResponsiveService.triggerSelectionFeedback(context);
                          _clearSelection();
                        },
                        icon: Icon(Icons.clear, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                        label: const Text('Clear Selection'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, ResponsiveService.getTouchTargetSize(context)),
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 12)),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isValidating ? null : () {
                          ResponsiveService.triggerMediumFeedback(context);
                          _validateSelection();
                        },
                        icon: _isValidating
                            ? SizedBox(
                                width: ResponsiveService.getAdaptiveIconSize(context, 16),
                                height: ResponsiveService.getAdaptiveIconSize(context, 16),
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.verified_user, size: ResponsiveService.getAdaptiveIconSize(context, 18)),
                        label: Text(_isValidating ? 'Validating...' : 'Validate Selection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          minimumSize: Size(0, ResponsiveService.getTouchTargetSize(context)),
                        ),
                      ),
                    ),
                  ],
                ),
                desktop: Row(
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
              ),
            ],
          ),
        ),
        // Course selection, validation results, or safe course results
        Expanded(
          child: _safeCourseResults.isNotEmpty
              ? _buildSafeCourseResults()
              : _validationResults.isNotEmpty
                  ? _buildValidationResults()
                  : _buildCourseSelection(),
        ),
      ],
    );
  }

  Widget _buildCourseSelection() {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        ResponsiveService.isMobile(context) ? 100 : 16,
      ),
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
        
        // Check completion status
        final availableSectionTypes = sectionsByType.keys.toSet();
        final selectedSectionTypes = courseSelections.keys.toSet();
        final isCompleteSelection = availableSectionTypes.every((type) => selectedSectionTypes.contains(type));
        final missingSectionTypes = availableSectionTypes.difference(selectedSectionTypes);
        
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
                      color: isCompleteSelection ? Colors.green : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (missingSectionTypes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Still needed: ${missingSectionTypes.map((t) => _getSectionTypeName(t)).join(', ')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            trailing: isCompleteSelection
                ? Icon(Icons.check_circle, color: Colors.green)
                : hasSelections
                    ? Icon(Icons.warning, color: Colors.orange)
                    : const Icon(Icons.radio_button_unchecked),
            children: [
              // Show exam information first
              if (course.midSemExam != null || course.endSemExam != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Exam Schedule',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (course.midSemExam != null) ...[
                        _buildExamInfo('Mid-Sem', course.midSemExam!),
                        if (course.endSemExam != null) const SizedBox(height: 4),
                      ],
                      if (course.endSemExam != null)
                        _buildExamInfo('Comprehensive', course.endSemExam!),
                    ],
                  ),
                ),
              // Then show sections
              ...sectionsByType.entries.map((typeEntry) {
                final sectionType = typeEntry.key;
                final sections = typeEntry.value;
                final selectedSectionId = courseSelections[sectionType];
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '${_getSectionTypeName(sectionType)} Sections',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (selectedSectionId != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Selected: $selectedSectionId',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                'Choose one',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
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
            }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExamInfo(String examType, ExamSchedule exam) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: examType == 'Mid-Sem' ? Colors.purple : Colors.deepOrange,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            examType,
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
            '${_formatDate(exam.date)} - ${TimeSlotInfo.getTimeSlotName(exam.timeSlot)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactExamInfo(String examType, ExamSchedule exam) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: examType == 'Mid-Sem' ? Colors.purple : Colors.deepOrange,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            examType == 'Mid-Sem' ? 'MS' : 'CE',
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_formatDate(exam.date)} - ${TimeSlotInfo.getTimeSlotName(exam.timeSlot)}',
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getSectionTypeName(SectionType type) {
    switch (type) {
      case SectionType.L:
        return 'Lecture';
      case SectionType.P:
        return 'Practical';
      case SectionType.T:
        return 'Tutorial';
    }
  }

  Widget _buildSafeCourseResults() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _safeCourseResults.clear();
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Course Selection'),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Found ${_safeCourseResults.length} courses that can be safely added',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (query) {
                  _safeCourseSearchQuery = query;
                  _filterSafeCourseResults();
                },
                decoration: InputDecoration(
                  hintText: 'Search safe courses...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _safeCourseSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _safeCourseSearchQuery = '';
                              _filteredSafeCourseResults = _safeCourseResults;
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              if (_filteredSafeCourseResults.length != _safeCourseResults.length) ...[
                const SizedBox(height: 8),
                Text(
                  'Showing ${_filteredSafeCourseResults.length} of ${_safeCourseResults.length} safe courses',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(),
        // Safe course results
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              ResponsiveService.isMobile(context) ? 100 : 16,
            ),
            itemCount: _filteredSafeCourseResults.length,
            itemBuilder: (context, index) {
              final result = _filteredSafeCourseResults[index];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Course header
                      Row(
                        children: [
                          Icon(
                            Icons.school,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.courseCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  result.courseTitle,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          // Action button to add this combination
                          ElevatedButton.icon(
                            onPressed: () => _addSafeCombination(result),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Safe combination details
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Safe Combination:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            
                            // Show sections in the combination
                            ...result.safeCombination.entries.map((entry) {
                              final sectionType = entry.key;
                              final sectionId = entry.value;
                              final section = result.course.sections.firstWhere(
                                (s) => s.sectionId == sectionId
                              );
                              
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getSectionTypeColor(sectionType),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        sectionType.name,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Section $sectionId',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (section.instructor.isNotEmpty)
                                            Text(
                                              'Instructor: ${section.instructor}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          if (section.room.isNotEmpty)
                                            Text(
                                              'Room: ${section.room}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          Text(
                                            'Schedule: ${_formatSchedule(section.schedule)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      
                      // Show exam information if available
                      if (result.course.midSemExam != null || result.course.endSemExam != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_outlined,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Exams',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (result.course.midSemExam != null) ...[
                                _buildCompactExamInfo('Mid-Sem', result.course.midSemExam!),
                                if (result.course.endSemExam != null) const SizedBox(height: 3),
                              ],
                              if (result.course.endSemExam != null)
                                _buildCompactExamInfo('Comprehensive', result.course.endSemExam!),
                            ],
                          ),
                        ),
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

  void _addSafeCombination(SafeCourseResult result) {
    // Create SelectedSection objects from the safe combination
    final List<SelectedSection> newSections = [];
    for (final entry in result.safeCombination.entries) {
      final sectionType = entry.key;
      final sectionId = entry.value;
      final section = result.course.sections.firstWhere((s) => s.sectionId == sectionId);
      
      newSections.add(SelectedSection(
        courseCode: result.courseCode,
        sectionId: sectionId,
        section: section,
      ));
    }
    
    // Add to current timetable
    setState(() {
      _currentTimetableSections.addAll(newSections);
      _selectedSections[result.courseCode] = Map.from(result.safeCombination);
      _safeCourseResults.clear();
      _filteredSafeCourseResults.clear();
      _safeCourseSearchQuery = '';
    });
    
    // Notify parent widget about the timetable update
    if (widget.onTimetableUpdated != null) {
      widget.onTimetableUpdated!(_currentTimetableSections);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.courseCode} added to your timetable!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              ResponsiveService.isMobile(context) ? 100 : 16,
            ),
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

class SafeCourseResult {
  final String courseCode;
  final String courseTitle;
  final Map<SectionType, String> safeCombination;
  final List<String> instructors;
  final List<String> rooms;
  final String scheduleDescription;
  final Course course;

  SafeCourseResult({
    required this.courseCode,
    required this.courseTitle,
    required this.safeCombination,
    required this.instructors,
    required this.rooms,
    required this.scheduleDescription,
    required this.course,
  });
}