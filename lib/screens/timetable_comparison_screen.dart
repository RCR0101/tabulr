import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import '../widgets/timetable_widget.dart';
import '../services/timetable_service.dart';
import '../services/all_course_service.dart';
import '../services/responsive_service.dart';
import '../services/secure_logger.dart';

enum ComparisonViewMode { grid, list }

class TimetableComparisonScreen extends StatefulWidget {
  const TimetableComparisonScreen({super.key});

  @override
  State<TimetableComparisonScreen> createState() => _TimetableComparisonScreenState();
}

class _TimetableComparisonScreenState extends State<TimetableComparisonScreen> {
  final TimetableService _timetableService = TimetableService();
  final AllCourseService _allCourseService = AllCourseService();
  
  List<Timetable> _allTimetables = [];
  Timetable? _leftTimetable;
  Timetable? _rightTimetable;
  ComparisonViewMode _viewMode = ComparisonViewMode.grid;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimetables();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force list view on mobile
    if (ResponsiveService.isMobile(context) && _viewMode == ComparisonViewMode.grid) {
      setState(() {
        _viewMode = ComparisonViewMode.list;
      });
    }
  }

  Future<void> _loadTimetables() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final timetables = await _timetableService.getAllTimetables();
      SecureLogger.dataOperation('load', 'timetables_for_comparison', true, {
        'timetable_count': timetables.length
      });
      
      setState(() {
        _allTimetables = timetables;
        _isLoading = false;
      });
      
      SecureLogger.dataOperation('load', 'comparison_timetables', true, {
        'timetable_count': timetables.length,
        'operation': 'load_for_comparison'
      });
    } catch (e) {
      SecureLogger.error('DATA', 'Error loading timetables for comparison', e, null, {
        'operation': 'load_comparison_timetables'
      });
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading timetables: $e')),
        );
      }
    }
  }

  List<TimetableSlot> _convertToTimetableSlots(Timetable timetable) {
    List<TimetableSlot> slots = [];
    
    for (var selectedSection in timetable.selectedSections) {
      // Find the course title with improved fallback
      String baseTitle = selectedSection.courseCode; // Default fallback
      
      try {
        final course = timetable.availableCourses.firstWhere(
          (c) => c.courseCode == selectedSection.courseCode,
        );
        baseTitle = course.courseTitle;
      } catch (e) {
        // Course not found in current semester
        // Try to get from cache or use course code as fallback
        final cachedTitle = _allCourseService.getCachedCourseTitle(selectedSection.courseCode, campus: timetable.campus);
        if (cachedTitle != null) {
          baseTitle = cachedTitle;
        }
        // If no cached title, baseTitle remains as courseCode
      }
      
      for (var scheduleEntry in selectedSection.section.schedule) {
        for (var day in scheduleEntry.days) {
          // Add section type info for non-lecture sections
          final courseTitle = selectedSection.section.type == SectionType.L 
            ? baseTitle
            : '$baseTitle (${selectedSection.section.type.name})';
            
          slots.add(TimetableSlot(
            day: day,
            hours: scheduleEntry.hours,
            courseCode: selectedSection.courseCode,
            courseTitle: courseTitle,
            sectionId: selectedSection.sectionId,
            instructor: selectedSection.section.instructor,
            room: selectedSection.section.room,
          ));
        }
      }
    }
    
    return slots;
  }

  Widget _buildTimetableSelector({
    required String label,
    required Timetable? selectedTimetable,
    required Function(Timetable?) onChanged,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<Timetable>(
                value: selectedTimetable,
                isExpanded: true,
                underline: Container(),
                hint: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text('Select a timetable'),
                ),
                onChanged: onChanged,
                menuMaxHeight: 400, // Limit dropdown height
                items: _allTimetables.asMap().entries.map((entry) {
                  final index = entry.key;
                  final timetable = entry.value;
                  
                  // Use name if not empty and not default, otherwise create a better name
                  String displayName;
                  if (timetable.name.isNotEmpty && timetable.name != 'Untitled Timetable') {
                    displayName = timetable.name;
                  } else {
                    // Create a name with index and creation date
                    final shortDate = _formatShortDate(timetable.createdAt);
                    displayName = 'Timetable ${index + 1} ($shortDate)';
                  }
                  
                  return DropdownMenuItem<Timetable>(
                    value: timetable,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  '${timetable.selectedSections.length} courses • ${timetable.campus.name.toLowerCase()}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDateTime(timetable.createdAt),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView() {
    if (_leftTimetable == null && _rightTimetable == null) {
      return const Center(
        child: Text('Select timetables to compare'),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _leftTimetable != null
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Text(
                            _leftTimetable!.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created ${_formatDateTime(_leftTimetable!.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TimetableWidget(
                        timetableSlots: _convertToTimetableSlots(_leftTimetable!),
                        size: TimetableSize.compact,
                        incompleteSelectionWarnings: const [],
                      ),
                    ),
                  ],
                )
              : const Center(child: Text('Select left timetable')),
        ),
        Container(
          width: 1,
          color: Theme.of(context).colorScheme.outline,
        ),
        Expanded(
          child: _rightTimetable != null
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Text(
                            _rightTimetable!.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created ${_formatDateTime(_rightTimetable!.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TimetableWidget(
                        timetableSlots: _convertToTimetableSlots(_rightTimetable!),
                        size: TimetableSize.compact,
                        incompleteSelectionWarnings: const [],
                      ),
                    ),
                  ],
                )
              : const Center(child: Text('Select right timetable')),
        ),
      ],
    );
  }

  Widget _buildListView() {
    if (_leftTimetable == null || _rightTimetable == null) {
      return const Center(
        child: Text('Select both timetables to see detailed comparison'),
      );
    }

    final leftCourses = _leftTimetable!.selectedSections;
    final rightCourses = _rightTimetable!.selectedSections;
    
    // Create comparison data - compare by course code + section type
    final comparisonItems = <ComparisonItem>[];
    final processedSections = <String>{};
    
    // Process left timetable sections
    for (var leftSection in leftCourses) {
      final sectionKey = '${leftSection.courseCode}_${leftSection.section.type.name}';
      
      // Find matching section with same course code AND same section type
      final rightMatches = rightCourses.where(
        (r) => r.courseCode == leftSection.courseCode && 
               r.section.type == leftSection.section.type,
      ).toList();
      
      if (rightMatches.isNotEmpty) {
        // Course + section type exists in both timetables
        final rightMatch = rightMatches.first;
        comparisonItems.add(ComparisonItem(
          courseCode: '${leftSection.courseCode} (${leftSection.section.type.name})',
          courseName: _getCourseTitle(leftSection.courseCode, _leftTimetable!),
          leftSection: leftSection,
          rightSection: rightMatch,
          status: leftSection.sectionId == rightMatch.sectionId
              ? ComparisonStatus.sameCourse
              : ComparisonStatus.differentSection,
        ));
      } else {
        // This course + section type combination only in left
        comparisonItems.add(ComparisonItem(
          courseCode: '${leftSection.courseCode} (${leftSection.section.type.name})',
          courseName: _getCourseTitle(leftSection.courseCode, _leftTimetable!),
          leftSection: leftSection,
          rightSection: null,
          status: ComparisonStatus.onlyInLeft,
        ));
      }
      processedSections.add(sectionKey);
    }
    
    // Process right timetable sections that weren't already processed
    for (var rightSection in rightCourses) {
      final sectionKey = '${rightSection.courseCode}_${rightSection.section.type.name}';
      
      if (!processedSections.contains(sectionKey)) {
        comparisonItems.add(ComparisonItem(
          courseCode: '${rightSection.courseCode} (${rightSection.section.type.name})',
          courseName: _getCourseTitle(rightSection.courseCode, _rightTimetable!),
          leftSection: null,
          rightSection: rightSection,
          status: ComparisonStatus.onlyInRight,
        ));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildComparisonSummary(comparisonItems),
          const SizedBox(height: 24),
          Text(
            'Detailed Comparison',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...comparisonItems.map((item) => _buildComparisonItem(item)),
        ],
      ),
    );
  }

  Widget _buildComparisonSummary(List<ComparisonItem> items) {
    final sameCourses = items.where((i) => i.status == ComparisonStatus.sameCourse).length;
    final differentSections = items.where((i) => i.status == ComparisonStatus.differentSection).length;
    final onlyInLeft = items.where((i) => i.status == ComparisonStatus.onlyInLeft).length;
    final onlyInRight = items.where((i) => i.status == ComparisonStatus.onlyInRight).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comparison Summary',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Identical Courses',
                    sameCourses.toString(),
                    Icons.check_circle,
                    Colors.green,
                    ComparisonStatus.sameCourse,
                    items,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'Different Sections',
                    differentSections.toString(),
                    Icons.swap_horiz,
                    Colors.orange,
                    ComparisonStatus.differentSection,
                    items,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Only in ${_leftTimetable!.name}',
                    onlyInLeft.toString(),
                    Icons.arrow_left,
                    Colors.blue,
                    ComparisonStatus.onlyInLeft,
                    items,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'Only in ${_rightTimetable!.name}',
                    onlyInRight.toString(),
                    Icons.arrow_right,
                    Colors.purple,
                    ComparisonStatus.onlyInRight,
                    items,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title, 
    String value, 
    IconData icon, 
    Color color, 
    ComparisonStatus filterStatus,
    List<ComparisonItem> allItems,
  ) {
    final filteredItems = allItems.where((item) => item.status == filterStatus).toList();
    
    return GestureDetector(
      onTap: () => _showCoursesDialog(title, filteredItems, color, icon),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Icon(
              Icons.touch_app,
              size: 12,
              color: color.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showCoursesDialog(String title, List<ComparisonItem> items, Color color, IconData icon) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(
                      bottom: BorderSide(
                        color: color.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            Text(
                              '${items.length} courses',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
                // Course list
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No courses found',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _buildDialogCourseItem(item, color);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogCourseItem(ComparisonItem item, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.courseCode,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.courseName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (item.status == ComparisonStatus.differentSection) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSectionInfo('Left', item.leftSection),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSectionInfo('Right', item.rightSection),
                ),
              ],
            ),
          ] else if (item.status == ComparisonStatus.onlyInLeft && item.leftSection != null) ...[
            const SizedBox(height: 8),
            _buildSectionInfo('Section Details', item.leftSection),
          ] else if (item.status == ComparisonStatus.onlyInRight && item.rightSection != null) ...[
            const SizedBox(height: 8),
            _buildSectionInfo('Section Details', item.rightSection),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionInfo(String label, SelectedSection? section) {
    if (section == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${section.sectionId} (${section.section.type.name})',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          section.section.instructor,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonItem(ComparisonItem item) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (item.status) {
      case ComparisonStatus.sameCourse:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Same course and section';
        break;
      case ComparisonStatus.differentSection:
        statusColor = Colors.orange;
        statusIcon = Icons.swap_horiz;
        statusText = 'Different section';
        break;
      case ComparisonStatus.onlyInLeft:
        statusColor = Colors.blue;
        statusIcon = Icons.arrow_left;
        statusText = 'Only in ${_leftTimetable!.name}';
        break;
      case ComparisonStatus.onlyInRight:
        statusColor = Colors.purple;
        statusIcon = Icons.arrow_right;
        statusText = 'Only in ${_rightTimetable!.name}';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                        item.courseCode,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.courseName,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.status != ComparisonStatus.onlyInLeft && 
                item.status != ComparisonStatus.onlyInRight) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSectionDetails(
                      'Left: ${_leftTimetable!.name}',
                      item.leftSection,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSectionDetails(
                      'Right: ${_rightTimetable!.name}',
                      item.rightSection,
                    ),
                  ),
                ],
              ),
            ] else if (item.status == ComparisonStatus.onlyInLeft) ...[
              const SizedBox(height: 12),
              _buildSectionDetails(
                'From: ${_leftTimetable!.name}',
                item.leftSection,
              ),
            ] else if (item.status == ComparisonStatus.onlyInRight) ...[
              const SizedBox(height: 12),
              _buildSectionDetails(
                'From: ${_rightTimetable!.name}',
                item.rightSection,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionDetails(String title, SelectedSection? section) {
    if (section == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Section: ${section.sectionId} (${section.section.type.name})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text('Instructor: ${section.section.instructor}'),
              Text('Room: ${section.section.room}'),
              if (section.section.schedule.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...section.section.schedule.map((schedule) => Text(
                  '${schedule.days.map((d) => d.name).join(', ')} • Hours: ${schedule.hours.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _getCourseTitle(String courseCode, Timetable timetable) {
    // First try to find in available courses
    try {
      final course = timetable.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
      );
      return course.courseTitle;
    } catch (e) {
      // Course not found in current semester, return course code for now
      // The grid view will handle the proper fallback with async loading
      return courseCode;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays < 1) {
      if (difference.inHours < 1) {
        return '${difference.inMinutes} minutes ago';
      } else {
        return '${difference.inHours} hours ago';
      }
    } else if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else {
      final months = difference.inDays ~/ 30;
      if (months < 12) {
        return '$months months ago';
      } else {
        final years = months ~/ 12;
        return '$years years ago';
      }
    }
  }

  String _formatShortDate(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Timetables'),
        actions: [
          // Hide grid/list toggle on mobile, show only on tablet/desktop
          if (!ResponsiveService.isMobile(context))
            SegmentedButton<ComparisonViewMode>(
              segments: const [
                ButtonSegment(
                  value: ComparisonViewMode.grid,
                  icon: Icon(Icons.grid_view),
                  label: Text('Grid'),
                ),
                ButtonSegment(
                  value: ComparisonViewMode.list,
                  icon: Icon(Icons.list),
                  label: Text('List'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (Set<ComparisonViewMode> selection) {
                ResponsiveService.triggerSelectionFeedback(context);
                setState(() {
                  _viewMode = selection.first;
                });
              },
            ),
          SizedBox(width: ResponsiveService.isMobile(context) ? 8 : 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildTimetableSelector(
                        label: 'Left Timetable',
                        selectedTimetable: _leftTimetable,
                        onChanged: (timetable) {
                          setState(() {
                            _leftTimetable = timetable;
                          });
                        },
                      ),
                      const SizedBox(width: 16),
                      _buildTimetableSelector(
                        label: 'Right Timetable',
                        selectedTimetable: _rightTimetable,
                        onChanged: (timetable) {
                          setState(() {
                            _rightTimetable = timetable;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ResponsiveService.isMobile(context) || _viewMode == ComparisonViewMode.list
                      ? _buildListView()
                      : _buildGridView(),
                ),
              ],
            ),
    );
  }
}

class ComparisonItem {
  final String courseCode;
  final String courseName;
  final SelectedSection? leftSection;
  final SelectedSection? rightSection;
  final ComparisonStatus status;

  ComparisonItem({
    required this.courseCode,
    required this.courseName,
    required this.leftSection,
    required this.rightSection,
    required this.status,
  });
}

enum ComparisonStatus {
  sameCourse,
  differentSection,
  onlyInLeft,
  onlyInRight,
}