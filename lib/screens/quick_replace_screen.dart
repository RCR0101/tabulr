import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/course_comparison_service.dart';

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

  // Get unique courses from selected sections
  List<Course> get _selectedCourses {
    final selectedCourseCodes = widget.selectedSections
        .map((section) => section.courseCode)
        .toSet();
    
    return widget.availableCourses
        .where((course) => selectedCourseCodes.contains(course.courseCode))
        .toList();
  }

  void _findSimilarCourses() async {
    if (_selectedCourse == null) return;

    setState(() {
      _isLoading = true;
    });

    // Find similar courses in a microtask to avoid blocking UI
    await Future.microtask(() {
      final comparisons = CourseComparisonService.findSimilarCourses(
        _selectedCourse!,
        widget.availableCourses,
        limit: 30,
      );
      
      setState(() {
        _similarCourses = comparisons;
        _isLoading = false;
      });
    });
  }

  List<CourseComparison> get _filteredCourses {
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
            // Compact Course Selection (Always visible)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.school,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Select Course to Replace',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<Course>(
                    initialValue: _selectedCourse,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: 'Choose a course from your timetable...',
                      prefixIcon: const Icon(Icons.book, size: 20),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    isExpanded: true,
                    items: _selectedCourses.map((course) {
                      return DropdownMenuItem(
                        value: course,
                        child: Row(
                          children: [
                            Text(
                              course.courseCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                course.courseTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                      if (course != null) {
                        _findSimilarCourses();
                      }
                    },
                  ),
                ],
              ),
            ),
            
            // Show content only when a course is selected
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
              
              // Search Bar
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search similar courses...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              setState(() {
                                _searchText = '';
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchText = value;
                    });
                  },
                ),
              ),
              
              // Results Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
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
              ),
              
              // Similar Courses List
              Expanded(
                child: _isLoading
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
                            child: Text(
                              course.courseCode,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: canReplace 
                                  ? null 
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
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
}