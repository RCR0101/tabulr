import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'course_list_widget.dart';
import 'exam_dates_widget.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';

class CoursesTabWidget extends StatefulWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String, String, bool) onSectionToggle;
  final int projectCount;
  final ValueChanged<int> onProjectCountChanged;

  const CoursesTabWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
    required this.projectCount,
    required this.onProjectCountChanged,
  });

  @override
  State<CoursesTabWidget> createState() => _CoursesTabWidgetState();
}

class _CoursesTabWidgetState extends State<CoursesTabWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildStickyCreditsBar() {
    final selectedCoursesCodes = widget.selectedSections.map((s) => s.courseCode).toSet();
    double courseCredits = 0;

    for (final courseCode in selectedCoursesCodes) {
      final course = widget.courses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(courseCode: courseCode, courseTitle: 'Unknown', lectureCredits: 0.0, practicalCredits: 0.0, totalCredits: 0.0, sections: []),
      );
      courseCredits += course.totalCredits;
    }

    final projectCredits = widget.projectCount * 3;
    final totalCredits = courseCredits + projectCredits;
    final scheme = Theme.of(context).colorScheme;
    final isOver = totalCredits > 25;
    final canAddProject = totalCredits + 3 <= 25 && widget.projectCount < 8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOver ? scheme.errorContainer : scheme.primaryContainer.withValues(alpha: AppDesign.opacityLow),
        border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: AppDesign.opacityLow))),
      ),
      child: Row(
        children: [
          Icon(Icons.school, size: 16, color: isOver ? scheme.error : scheme.primary),
          const SizedBox(width: 6),
          Text(
            '${totalCredits % 1 == 0 ? totalCredits.toInt() : totalCredits.toStringAsFixed(1)}/25 credits',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isOver ? scheme.error : scheme.primary),
          ),
          if (selectedCoursesCodes.isNotEmpty) ...[
            Text(
              '  (${selectedCoursesCodes.length} course${selectedCoursesCodes.length != 1 ? 's' : ''})',
              style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
            ),
          ],
          const Spacer(),
          // Project counter inline
          Text('Projects', style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
          const SizedBox(width: 4),
          InkWell(
            onTap: widget.projectCount > 0 ? () { widget.onProjectCountChanged(widget.projectCount - 1); } : null,
            child: Icon(Icons.remove_circle_outline, size: 16, color: widget.projectCount > 0 ? scheme.primary : scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${widget.projectCount}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
          ),
          InkWell(
            onTap: canAddProject
                ? () { widget.onProjectCountChanged(widget.projectCount + 1); }
                : () { if (totalCredits + 3 > 25) ToastService.showError('Cannot add project — would exceed 25 credit limit'); },
            child: Icon(Icons.add_circle_outline, size: 16, color: canAddProject ? scheme.primary : scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
          ),
          if (widget.projectCount > 0) ...[
            const SizedBox(width: 4),
            Text('(+$projectCredits)', style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow))),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
    
    return Column(
      children: [
        _buildStickyCreditsBar(),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
            indicatorColor: Theme.of(context).colorScheme.primary,
            dividerColor: Theme.of(context).colorScheme.outline,
            isScrollable: false,
            labelPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 4) : null,
            tabAlignment: TabAlignment.fill,
            tabs: isMobile ? [
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Search',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.courses.length})',
                        style: TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Selected',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.selectedSections.map((s) => s.courseCode).toSet().length})',
                        style: TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Exams',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] : [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search, size: 16),
                    const SizedBox(width: 4),
                    Text('Search (${widget.courses.length})', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, size: 16),
                    const SizedBox(width: 4),
                    Text('My Courses (${widget.selectedSections.map((s) => s.courseCode).toSet().length})', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16),
                    const SizedBox(width: 4),
                    const Text('Exams', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Search tab - shows all courses without reordering
              CourseListWidget(
                courses: widget.courses,
                selectedSections: widget.selectedSections,
                onSectionToggle: widget.onSectionToggle,
                showOnlySelected: false,
              ),
              // My Courses tab - shows only selected courses
              CourseListWidget(
                courses: widget.courses,
                selectedSections: widget.selectedSections,
                onSectionToggle: widget.onSectionToggle,
                showOnlySelected: true,
              ),
              // Exam schedule tab
              widget.selectedSections.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No courses selected',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add courses to see exam schedules',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ExamDatesWidget(
                        selectedSections: widget.selectedSections,
                        courses: widget.courses,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}