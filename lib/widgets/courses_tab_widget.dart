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
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF21262D),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Color(0xFF58A6FF),
            unselectedLabelColor: Color(0xFF8B949E),
            indicatorColor: Color(0xFF58A6FF),
            dividerColor: Color(0xFF30363D),
            tabs: [
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
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 64,
                            color: Color(0xFF656D76),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No courses selected',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF8B949E),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add courses to see exam schedules',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF656D76),
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