import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../utils/design_constants.dart';
import '../models/timetable_constraints.dart';
import '../models/timetable.dart' as timetable;
import '../services/data/course_data_service.dart';
import '../services/data/campus_service.dart';
import '../services/core/sample_timetable_service.dart';
import '../services/ui/toast_service.dart';
import '../widgets/timetable_generator_widget.dart';
import '../widgets/error_dialog.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';

/// How the editor should consume a chosen generated timetable.
enum GeneratorApplyMode { applyToCurrent, saveAsNew }

/// The generator's return value: the picked sections plus whether they replace
/// the current timetable or become a brand-new one (keeping the current intact).
class GeneratorSelection {
  final List<timetable.SelectedSection> sections;
  final GeneratorApplyMode mode;
  final String suggestedName;

  GeneratorSelection({
    required this.sections,
    required this.mode,
    required this.suggestedName,
  });
}

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final CourseDataService _courseDataService = CourseDataService();
  List<Course> _availableCourses = [];
  bool _isLoading = true;
  StreamSubscription<Campus>? _campusSubscription;

  // Bumped per load; a stale campus-change reload that finishes late compares
  // unequal and drops its result instead of overwriting fresher data.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadCourses();

    // Listen for campus changes
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      _loadCourses();
    });
  }

  @override
  void dispose() {
    _campusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    final seq = ++_loadSeq;
    try {
      setState(() {
        _isLoading = true;
      });

      // Load courses directly for current campus without affecting campus selection
      final courses = await _courseDataService.fetchCourses();

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _availableCourses = courses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Error loading courses: $e');
    }
  }

  void _showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  /// Drops the "A. " option-letter prefix so the descriptor reads as a clean
  /// timetable name (e.g. "A. 3-day week" → "3-day week").
  String _nameFromOption(String id) =>
      id.replaceFirst(RegExp(r'^[A-Z]\.\s*'), '').trim();

  void _onTimetableSelected(GeneratedTimetable generated) {
    // Convert SelectedSection from timetable_constraints to timetable models
    final timetableSections = generated.sections.map((s) => timetable.SelectedSection(
      courseCode: s.courseCode,
      sectionId: s.sectionId,
      section: s.section,
    )).toList();

    final suggestedName = _nameFromOption(generated.id);

    void finish(GeneratorApplyMode mode) {
      Navigator.pop(context); // dismiss dialog
      if (mode == GeneratorApplyMode.saveAsNew) {
        // Persist it as its own timetable and stay on the generator so the user
        // can keep saving more options. Only "apply to current" leaves.
        _saveAsNewTimetable(timetableSections, suggestedName);
      } else {
        Navigator.pop(
          context,
          GeneratorSelection(
            sections: timetableSections,
            mode: mode,
            suggestedName: suggestedName,
          ),
        );
      }
    }

    AppDialog.adaptive(
      context: context,
      title: 'Use this timetable',
      icon: Icons.check_circle_outline,
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
          const SizedBox(height: 12),
          Text(
            'Replace what you\'re editing, or keep it and save this as a new timetable?',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
        AppButton(
          label: 'Save as New',
          variant: AppButtonVariant.secondary,
          onTap: () => finish(GeneratorApplyMode.saveAsNew),
        ),
        AppButton(
          label: 'Apply to Current',
          onTap: () => finish(GeneratorApplyMode.applyToCurrent),
        ),
      ],
    );
  }

  Future<void> _saveAsNewTimetable(
    List<timetable.SelectedSection> sections,
    String suggestedName,
  ) async {
    try {
      final tt = await SampleTimetableService.saveAsNew(sections, suggestedName);
      if (!mounted) return;
      ToastService.showSuccess('Saved as new timetable "${tt.name}"');
    } catch (e) {
      if (mounted) ErrorDialog.show(context, 'Error saving new timetable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.auto_awesome_mosaic,
          title: 'Timetable Generator',
          subtitle: 'Automatic Scheduling',
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading courses...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No courses available',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please ensure course data is loaded',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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