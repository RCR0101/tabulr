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
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.courses.length})',
                        style: TextStyle(fontSize: 8),
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
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.selectedSections.map((s) => s.courseCode).toSet().length})',
                        style: TextStyle(fontSize: 8),
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
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
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
                    Text('Search (${widget.courses.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, size: 16),
                    const SizedBox(width: 4),
                    Text('My Courses (${widget.selectedSections.map((s) => s.courseCode).toSet().length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16),
                    const SizedBox(width: 4),
                    const Text('Exams'),
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