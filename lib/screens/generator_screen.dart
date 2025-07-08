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
      appBar: AppBar(
        title: const Text('Advanced Timetable Generator'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TimetableGeneratorWidget(
              availableCourses: _availableCourses,
              onTimetableSelected: _onTimetableSelected,
            ),
    );
  }
}