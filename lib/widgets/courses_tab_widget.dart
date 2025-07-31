import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'course_list_widget.dart';
import 'exam_dates_widget.dart';

class CoursesTabWidget extends StatefulWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String, String, bool) onSectionToggle;

  const CoursesTabWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
  });

  @override
  State<CoursesTabWidget> createState() => _CoursesTabWidgetState();
}

class _CoursesTabWidgetState extends State<CoursesTabWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isBannerExpanded = false;
  int _projectCount = 0;

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

  Widget _buildCreditsBanner() {
    // Calculate total credits from selected courses
    final selectedCoursesCodes = widget.selectedSections.map((s) => s.courseCode).toSet();
    int courseCredits = 0;
    
    for (final courseCode in selectedCoursesCodes) {
      final course = widget.courses.firstWhere(
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
      courseCredits += course.totalCredits;
    }
    
    final projectCredits = _projectCount * 3;
    final totalCredits = courseCredits + projectCredits;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Main banner with expandable functionality
          InkWell(
            onTap: () {
              setState(() {
                _isBannerExpanded = !_isBannerExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total Credits: $totalCredits (Max: 25)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Icon(
                    _isBannerExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Collapsible project section
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Divider(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.assignment,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Projects:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _projectCount > 0 ? () {
                              setState(() {
                                _projectCount--;
                              });
                            } : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            iconSize: 20,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 40),
                            child: Text(
                              '$_projectCount',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            onPressed: _projectCount < 8 ? () { // Max 8 projects (24 credits)
                              setState(() {
                                _projectCount++;
                              });
                            } : null,
                            icon: const Icon(Icons.add_circle_outline),
                            iconSize: 20,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_projectCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_projectCount project${_projectCount == 1 ? '' : 's'} = +$projectCredits credits',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _isBannerExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
              Column(
                children: [
                  Expanded(
                    child: CourseListWidget(
                      courses: widget.courses,
                      selectedSections: widget.selectedSections,
                      onSectionToggle: widget.onSectionToggle,
                      showOnlySelected: true,
                    ),
                  ),
                  _buildCreditsBanner(),
                ],
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
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No courses selected',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add courses to see exam schedules',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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