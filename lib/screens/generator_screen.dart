import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../models/timetable.dart' as timetable;
import '../services/timetable_service.dart';
import '../widgets/timetable_generator_widget.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final TimetableService _timetableService = TimetableService();
  List<Course> _availableCourses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final timetable = await _timetableService.loadTimetable();
      setState(() {
        _availableCourses = timetable.availableCourses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Error loading courses: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onTimetableSelected(List<ConstraintSelectedSection> sections) {
    // Convert SelectedSection from timetable_constraints to timetable models
    final timetableSections = sections.map((s) => timetable.SelectedSection(
      courseCode: s.courseCode,
      sectionId: s.sectionId,
      section: s.section,
    )).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Timetable Selected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selected timetable with sections:'),
            const SizedBox(height: 8),
            ...timetableSections.map((section) => Text(
              '• ${section.courseCode} - ${section.sectionId}',
              style: const TextStyle(fontSize: 12),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, timetableSections);
            },
            child: const Text('Apply to Main Timetable'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF58A6FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF58A6FF),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Timetable Generator',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF0F6FC),
                  ),
                ),
                Text(
                  'Automatic Scheduling',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFF0F6FC)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF58A6FF),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading courses...',
                    style: TextStyle(
                      color: const Color(0xFF8B949E),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : _availableCourses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 64,
                        color: const Color(0xFF8B949E),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No courses available',
                        style: TextStyle(
                          color: const Color(0xFFF0F6FC),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please ensure course data is loaded',
                        style: TextStyle(
                          color: const Color(0xFF8B949E),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  child: TimetableGeneratorWidget(
                    availableCourses: _availableCourses,
                    onTimetableSelected: _onTimetableSelected,
                  ),
                ),
    );
  }
}