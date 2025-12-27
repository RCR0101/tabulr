import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_comparison_service.dart';
import '../services/humanities_electives_service.dart';
import '../services/discipline_electives_service.dart';
import '../services/secure_logger.dart';

enum CourseCategory { huel, del, other }

class QuickReplaceScreen extends StatefulWidget {
  final List<Course> availableCourses;
  final List<SelectedSection> selectedSections;
  final Function(Course selectedCourse, Course replacementCourse) onReplace;

  const QuickReplaceScreen({
    super.key,
    required this.availableCourses,
    required this.selectedSections,
    required this.onReplace,
  });

  @override
  State<QuickReplaceScreen> createState() => _QuickReplaceScreenState();
}

class _QuickReplaceScreenState extends State<QuickReplaceScreen> {
  Course? _selectedCourse;
  List<CourseComparison> _similarCourses = [];
  bool _isLoading = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Category filtering
  bool _isLoadingCategories = false;
  Set<String> _huelCourses = {};
  Set<String> _delCourses = {};
  Set<CourseCategory> _selectedCategories = {CourseCategory.huel, CourseCategory.other}; // DEL not selected by default
  
  // DEL-specific filtering parameters
  List<BranchInfo> _availableBranches = [];
  String? _primaryBranch;
  String? _secondaryBranch;
  String? _primarySemester;
  String? _secondarySemester;
  
  // UI state
  bool _isSearchParamsExpanded = true;
  
  final HumanitiesElectivesService _huelService = HumanitiesElectivesService();
  final DisciplineElectivesService _delService = DisciplineElectivesService();
  
  // Common semester options (simplified)
  static const List<String> _semesterOptions = [
    '1-1', '1-2', '2-1', '2-2', '3-1', '3-2'
  ];

  @override
  void initState() {
    super.initState();
    _loadCourseCategories();
  }

  // Load course categories from Firebase
  Future<void> _loadCourseCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      // Load available branches first (needed for DEL dropdowns)
      _availableBranches = await _delService.getAvailableBranches();
      
      // Load HUEL courses
      final huelCourses = await _huelService.getAllHumanitiesElectives(widget.availableCourses);
      _huelCourses = huelCourses.map((course) => course.courseCode).toSet();

      // Don't load DEL courses automatically - only when DEL category is selected
      // and user has configured branch/semester
      
      SecureLogger.info('COURSE', 'Loaded course categories', {'huel_count': _huelCourses.length});
    } catch (e) {
      SecureLogger.error('COURSE', 'Failed to load course categories', e);
    } finally {
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }
  
  // Load DEL courses based on selected branch and semester
  Future<void> _loadDelCourses() async {
    if (_primaryBranch != null && _primarySemester != null) {
      try {
        // Load filtered DEL courses with clash detection
        final delElectives = await _delService.getFilteredDisciplineElectivesWithClashDetection(
          _primaryBranch!,
          _secondaryBranch,
          _primarySemester!,
          _secondarySemester,
          widget.availableCourses,
        );
        _delCourses = delElectives.map((del) => del.courseCode).toSet();
      } catch (e) {
        SecureLogger.error('COURSE', 'Failed to load DEL courses', e);
        // Fallback to all DEL courses
        await _loadAllDelCourses();
      }
    } else {
      // Load all DEL courses if no specific branch/semester selected
      await _loadAllDelCourses();
    }
  }
  
  // Load all DEL courses (fallback method)
  Future<void> _loadAllDelCourses() async {
    final allDelCourses = <String>{};
    
    for (final branch in _availableBranches) {
      final delCourses = await _delService.getDisciplineElectives(branch.name);
      allDelCourses.addAll(delCourses.map((course) => course.courseCode));
    }
    _delCourses = allDelCourses;
  }

  // Get unique courses from selected sections
  List<Course> get _selectedCourses {
    final selectedCourseCodes = widget.selectedSections
        .map((section) => section.courseCode)
        .toSet();
    
    return widget.availableCourses
        .where((course) => selectedCourseCodes.contains(course.courseCode))
        .toList();
  }

  // Determine course category
  CourseCategory _getCourseCategory(String courseCode) {
    if (_huelCourses.contains(courseCode)) {
      return CourseCategory.huel;
    } else if (_delCourses.contains(courseCode)) {
      return CourseCategory.del;
    } else {
      return CourseCategory.other;
    }
  }

  // Get category display name
  String _getCategoryDisplayName(CourseCategory category) {
    switch (category) {
      case CourseCategory.huel:
        return 'HUELs';
      case CourseCategory.del:
        return 'DELs';
      case CourseCategory.other:
        return 'Other';
    }
  }
  
  // Check if search can be performed
  bool _canSearch() {
    // Must have selected a course
    if (_selectedCourse == null) return false;
    
    // Must have selected at least one category
    if (_selectedCategories.isEmpty) return false;
    
    // If DEL is selected, must have branch and semester
    if (_selectedCategories.contains(CourseCategory.del)) {
      if (_primaryBranch == null || _primarySemester == null) {
        return false;
      }
    }
    
    return true;
  }
  
  // Get validation message
  String _getValidationMessage() {
    if (_selectedCourse == null) {
      return 'Please select a course to replace';
    }
    
    if (_selectedCategories.isEmpty) {
      return 'Please select at least one course category';
    }
    
    if (_selectedCategories.contains(CourseCategory.del)) {
      if (_primaryBranch == null || _primarySemester == null) {
        return 'Please select branch and semester for DEL courses';
      }
    }
    
    return '';
  }

  void _findSimilarCourses() async {
    if (_selectedCourse == null) return;

    setState(() {
      _isLoading = true;
    });

    // Find similar courses in a microtask to avoid blocking UI
    await Future.microtask(() {
      // First filter available courses by selected categories
      final filteredCoursePool = _getFilteredCoursePool();
      
      final comparisons = CourseComparisonService.findSimilarCourses(
        _selectedCourse!,
        filteredCoursePool,
        limit: 50, // Increased limit since we're pre-filtering
      );
      
      setState(() {
        _similarCourses = comparisons;
        _isLoading = false;
      });
    });
  }
  
  // Get filtered course pool based on selected categories
  List<Course> _getFilteredCoursePool() {
    if (_selectedCategories.isEmpty) {
      return []; // No courses if no categories selected
    }
    
    return widget.availableCourses.where((course) {
      final category = _getCourseCategory(course.courseCode);
      return _selectedCategories.contains(category);
    }).toList();
  }

  List<CourseComparison> get _filteredCourses {
    // Only apply search text filtering since category filtering happens at course pool level
    if (_searchText.isEmpty) return _similarCourses;
    
    final lowercaseSearch = _searchText.toLowerCase();
    return _similarCourses
        .where((comparison) =>
            comparison.course.courseCode.toLowerCase().contains(lowercaseSearch) ||
            comparison.course.courseTitle.toLowerCase().contains(lowercaseSearch))
        .toList();
  }

  void _performReplace(Course replacementCourse) {
    // Check if both courses have only lecture sections
    if (!_canReplaceCourses(_selectedCourse!, replacementCourse)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Can only replace between courses that have only lecture sections'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    widget.onReplace(_selectedCourse!, replacementCourse);
    Navigator.of(context).pop();
  }

  bool _canReplaceCourses(Course selectedCourse, Course replacementCourse) {
    return CourseComparisonService.hasOnlyLectureSections(selectedCourse) && 
           CourseComparisonService.hasOnlyLectureSections(replacementCourse);
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Replace Course'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16), // Space between title bar and content
            
            // Course Selection (Always Visible) 
            _buildCourseSelection(),
            
            // Show course details when a course is selected (above search params)
            if (_selectedCourse != null) ...[
              // Compact Selected Course Details
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: _buildCompactCourseDetails(_selectedCourse!),
              ),
            ],
            
            // Search Parameters Section (Always Visible)
            _buildSearchParameters(),
            
            // Show results only when a course is selected and search has been performed
            if (_selectedCourse != null) ...[
              
              // Results Header
              if (_similarCourses.isNotEmpty || _isLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Similar Courses (${_filteredCourses.length})',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      
                      // Search field for filtering results - only show when courses are available
                      if (_similarCourses.isNotEmpty && !_isLoading) ...[
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: TextFormField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              hintText: 'Search in results...',
                              hintStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              suffixIcon: _searchText.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _searchText = '';
                                          _searchController.clear();
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchText = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              
              // Similar Courses List
              Expanded(
                child: _similarCourses.isEmpty && !_isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Ready to find courses',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click "Find Similar Courses" when ready',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _isLoading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Finding similar courses...'),
                              ],
                            ),
                          )
                        : _buildCompactSimilarCoursesList(),
              ),
            ] else ...[
              // Empty state when no course is selected
              Expanded(
                child: _buildEmptyState(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build course selection widget
  Widget _buildCourseSelection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Course to Replace',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Custom styled dropdown with better theming
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Theme.of(context).colorScheme.surface,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: DropdownButtonFormField<Course>(
                initialValue: _selectedCourse,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  hintText: 'Choose a course from your timetable...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.book_outlined, 
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                isExpanded: true,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                selectedItemBuilder: (context) {
                  return _selectedCourses.map((course) {
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            course.courseCode,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            course.courseTitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                items: _selectedCourses.map((course) {
                  return DropdownMenuItem(
                    value: course,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              course.courseCode,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              course.courseTitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (course) {
                  setState(() {
                    _selectedCourse = course;
                    _similarCourses.clear();
                    _searchText = '';
                    _searchController.clear();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Select a course from your timetable',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Find time-similar alternatives to replace it with',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCourseDetails(Course course) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              course.courseCode,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                course.courseTitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildCompactScheduleInfo(course),
      ],
    );
  }

  Widget _buildCompactScheduleInfo(Course course) {
    final List<Widget> items = [];

    // Lectures
    final lectures = course.sections.where((s) => s.type == SectionType.L).toList();
    if (lectures.isNotEmpty) {
      items.add(_buildCompactSection('L', lectures.first));
    }

    // Tutorials
    final tutorials = course.sections.where((s) => s.type == SectionType.T).toList();
    if (tutorials.isNotEmpty) {
      items.add(_buildCompactSection('T', tutorials.first));
    }

    // Practicals
    final practicals = course.sections.where((s) => s.type == SectionType.P).toList();
    if (practicals.isNotEmpty) {
      items.add(_buildCompactSection('P', practicals.first));
    }

    // Exams
    if (course.midSemExam != null || course.endSemExam != null) {
      final examTexts = <String>[];
      if (course.midSemExam != null) {
        examTexts.add('MidSem: ${course.midSemExam!.date.day}/${course.midSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot)}');
      }
      if (course.endSemExam != null) {
        examTexts.add('EndSem: ${course.endSemExam!.date.day}/${course.endSemExam!.date.month} ${TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot)}');
      }
      items.add(
        Row(
          children: [
            Icon(Icons.quiz, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                examTexts.join(', '),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: item,
      )).toList(),
    );
  }

  Widget _buildCompactSection(String type, Section section) {
    IconData icon;
    switch (type) {
      case 'L':
        icon = Icons.school;
        break;
      case 'T':
        icon = Icons.groups;
        break;
      case 'P':
        icon = Icons.science;
        break;
      default:
        icon = Icons.book;
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${section.sectionId}: ${TimeSlotInfo.getFormattedSchedule(section.schedule)}',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }



  Widget _buildCompactSimilarCoursesList() {
    if (_filteredCourses.isEmpty) {
      return const Center(
        child: Text(
          'No similar courses found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _filteredCourses.length,
      itemBuilder: (context, index) {
        final comparison = _filteredCourses[index];
        return _buildCompactCourseCard(comparison);
      },
    );
  }

  Widget _buildCompactCourseCard(CourseComparison comparison) {
    final course = comparison.course;
    final score = comparison.similarityScore;
    final canReplace = _canReplaceCourses(_selectedCourse!, course);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: canReplace ? () => _performReplace(course) : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: canReplace ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  course.courseCode,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: canReplace 
                                      ? null 
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (!_isLoadingCategories)
                                  _buildCategoryBadge(_getCourseCategory(course.courseCode)),
                              ],
                            ),
                          ),
                          if (!canReplace)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange, width: 1),
                              ),
                              child: const Text(
                                'Mixed Sections',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          if (canReplace)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getSimilarityColor(score).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _getSimilarityColor(score),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${(score * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _getSimilarityColor(score),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course.courseTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: canReplace 
                            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildCompactScheduleInfo(course),
                    ],
                  ),
                ),
                Icon(
                  canReplace ? Icons.arrow_forward : Icons.block,
                  size: 16,
                  color: canReplace 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }





  Color _getSimilarityColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.orange;
    if (score >= 0.4) return Colors.deepOrange;
    return Colors.red;
  }

  // Build category badge for course cards
  Widget _buildCategoryBadge(CourseCategory category) {
    Color badgeColor;
    String categoryText;
    
    switch (category) {
      case CourseCategory.huel:
        badgeColor = Colors.purple;
        categoryText = 'HUEL';
        break;
      case CourseCategory.del:
        badgeColor = Colors.blue;
        categoryText = 'DEL';
        break;
      case CourseCategory.other:
        badgeColor = Colors.grey;
        categoryText = 'OTHER';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor, width: 0.5),
      ),
      child: Text(
        categoryText,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }

  // Build comprehensive search parameters widget (collapsible)
  Widget _buildSearchParameters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible Header
          InkWell(
            onTap: () {
              setState(() {
                _isSearchParamsExpanded = !_isSearchParamsExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _isSearchParamsExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Search Parameters',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedCategories.isNotEmpty)
                    Text(
                      '${_selectedCategories.length} selected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _isSearchParamsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          
          // Expandable Content
          if (_isSearchParamsExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Course Category Selection
                  Text(
                    'Course Categories',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySelection(),
                  
                  const SizedBox(height: 16),
                  
                  // DEL-specific parameters (shown only if DEL is selected)
                  if (_selectedCategories.contains(CourseCategory.del))
                    _buildDelParametersSection(),
                  
                  const SizedBox(height: 16),
                  
                  // Find Courses Button
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: _canSearch() 
                              ? () => _findSimilarCourses()
                              : null,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.search, size: 20),
                          label: Text(
                            _isLoading ? 'Finding Courses...' : 'Find Similar Courses',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            minimumSize: const Size(double.infinity, 44),
                          ),
                        ),
                        
                        // Validation messages
                        if (!_canSearch())
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _getValidationMessage(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build category selection chips
  Widget _buildCategorySelection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: CourseCategory.values.map((category) {
        final isSelected = _selectedCategories.contains(category);
        final categoryName = _getCategoryDisplayName(category);
        
        return FilterChip(
          selected: isSelected,
          label: Text(
            categoryName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected 
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          onSelected: (selected) async {
            setState(() {
              if (selected) {
                _selectedCategories.add(category);
              } else {
                _selectedCategories.remove(category);
                // Clear DEL courses when DEL category is deselected
                if (category == CourseCategory.del) {
                  _delCourses.clear();
                }
              }
            });
            
            // Load DEL courses only when DEL category is selected AND we have branch/semester
            if (category == CourseCategory.del && selected) {
              await _loadDelCourses();
              setState(() {});
            }
          },
          selectedColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          side: BorderSide(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        );
      }).toList(),
    );
  }

  // Build DEL parameters section  
  Widget _buildDelParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DEL Parameters',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Primary Branch and Semester
              Text(
                'Primary Branch & Semester',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _primaryBranch,
                        decoration: InputDecoration(
                          labelText: 'Branch',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: _availableBranches.map((branch) {
                          return DropdownMenuItem(
                            value: branch.name,
                            child: Text(
                              branch.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() {
                            _primaryBranch = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _primarySemester,
                        decoration: InputDecoration(
                          labelText: 'Semester',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: _semesterOptions.map((semester) {
                          return DropdownMenuItem(
                            value: semester,
                            child: Text(
                              semester,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() {
                            _primarySemester = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Secondary Branch and Semester
              Text(
                'Secondary Branch & Semester',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _secondaryBranch,
                        decoration: InputDecoration(
                          labelText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'Branch',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          ..._availableBranches.map((branch) {
                            return DropdownMenuItem(
                              value: branch.name,
                              child: Text(
                                branch.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) async {
                          setState(() {
                            _secondaryBranch = value;
                            if (value == null) _secondarySemester = null;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Theme.of(context).colorScheme.surface,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _secondarySemester,
                        decoration: InputDecoration(
                          labelText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'Semester',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          ..._semesterOptions.map((semester) {
                            return DropdownMenuItem(
                              value: semester,
                              child: Text(
                                semester,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: _secondaryBranch != null ? (value) async {
                          setState(() {
                            _secondarySemester = value;
                          });
                          await _loadDelCourses();
                          setState(() {});
                        } : null,
                      ),
                    ),
                  ),
                ],
              ),
              
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

}