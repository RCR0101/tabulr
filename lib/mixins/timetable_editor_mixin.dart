import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:html' as html;
import '../models/course.dart';
import '../utils/page_transitions.dart';
import '../models/timetable.dart';
import '../models/timetable.dart' as timetable_models;
import '../models/export_options.dart';
import '../services/timetable_service.dart';
import '../services/course_utils.dart';
import '../services/export_service.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../services/auto_load_cdc_service.dart';
import '../services/campus_service.dart';
import '../services/page_leave_warning_service.dart';
import '../services/timetable_sharing_service.dart';
import '../services/undo_redo_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/share_timetable_dialog.dart';
import '../screens/generator_screen.dart';
import '../screens/add_swap_screen.dart';

mixin TimetableEditorMixin<T extends StatefulWidget> on State<T> {
  // Abstract getters/setters that subclasses must implement
  Timetable? get currentTimetable;
  bool get isSaving;
  set isSaving(bool value);
  bool get hasUnsavedChanges;
  set hasUnsavedChanges(bool value);
  GlobalKey get timetableKey;
  TimetableService get timetableService;
  AuthService get authService;
  PageLeaveWarningService get pageLeaveWarning;

  /// Class 1 does nothing; Class 2 calls widget.onUnsavedChangesChanged?.call(value)
  void onUnsavedChangesChanged(bool value);

  /// Already defined in both classes
  void triggerSavedIndicator();

  // -- Shared filteredCourses state --
  List<Course> get filteredCourses;
  set filteredCourses(List<Course> value);

  // -- Undo/Redo --
  final UndoRedoService undoRedoService = UndoRedoService();

  void _pushUndo(String description) {
    final tt = currentTimetable;
    if (tt != null) undoRedoService.pushState(tt, description);
  }

  void _applySnapshot(TimetableSnapshot snapshot) {
    final tt = currentTimetable;
    if (tt == null) return;
    tt.selectedSections.clear();
    tt.selectedSections.addAll(snapshot.sections);
    setState(() {
      hasUnsavedChanges = true;
    });
    onUnsavedChangesChanged(true);
    pageLeaveWarning.enableWarning(true);
  }

  void undo() {
    final tt = currentTimetable;
    if (tt == null) return;
    final snapshot = undoRedoService.undo(tt);
    if (snapshot != null) _applySnapshot(snapshot);
  }

  void redo() {
    final tt = currentTimetable;
    if (tt == null) return;
    final snapshot = undoRedoService.redo(tt);
    if (snapshot != null) _applySnapshot(snapshot);
  }

  Widget wrapWithKeyboardShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (hasUnsavedChanges && !isSaving) saveTimetable();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (hasUnsavedChanges && !isSaving) saveTimetable();
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Shared methods
  // -----------------------------------------------------------------------

  void onSearchChanged(String query, Map<String, dynamic> filters) {
    final tt = currentTimetable;
    if (tt == null) return;

    setState(() {
      var courses = tt.availableCourses;

      // Apply text search
      courses = CourseUtils.searchCourses(courses, query);

      // Apply course code filter
      if (filters['courseCode'] != null &&
          filters['courseCode'].toString().isNotEmpty) {
        courses = CourseUtils.filterByCourseCode(
          courses,
          filters['courseCode'],
        );
      }

      // Apply instructor filter
      if (filters['instructor'] != null &&
          filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(
          courses,
          filters['instructor'],
        );
      }

      // Apply credits filter
      courses = CourseUtils.filterByCredits(
        courses,
        filters['minCredits'],
        filters['maxCredits'],
      );

      // Apply days filter
      if (filters['days'] != null &&
          (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }

      // Apply hours filter
      if (filters['hours'] != null &&
          (filters['hours'] as List<int>).isNotEmpty) {
        courses = CourseUtils.filterByHours(courses, filters['hours']);
      }

      // Apply exam date filters
      if (filters['midSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['midSemDate'],
          true,
        );
      }

      if (filters['endSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['endSemDate'],
          false,
        );
      }

      filteredCourses = courses;
    });
  }

  void addSection(String courseCode, String sectionId) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      _pushUndo('Add $courseCode $sectionId');
      final success = timetableService.addSectionWithoutSaving(
        courseCode,
        sectionId,
        tt,
      );
      if (success) {
        setState(() {
          hasUnsavedChanges = true;
        });
        onUnsavedChangesChanged(true);
        pageLeaveWarning.enableWarning(true);
      } else {
        ToastService.showError('Cannot add — section clashes with your timetable');
      }
    } catch (e) {
      showErrorDialog('Error adding section: $e');
    }
  }

  void removeSection(String courseCode, String sectionId) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      _pushUndo('Remove $courseCode $sectionId');
      timetableService.removeSectionWithoutSaving(
        courseCode,
        sectionId,
        tt,
      );
      setState(() {
        hasUnsavedChanges = true;
      });
      onUnsavedChangesChanged(true);
    } catch (e) {
      showErrorDialog('Error removing section: $e');
    }
  }

  void quickReplaceCourse(Course selectedCourse, Course replacementCourse) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      _pushUndo('Replace ${selectedCourse.courseCode}');
      // Remove all sections of the selected course
      final sectionsToRemove = tt.selectedSections
          .where((section) => section.courseCode == selectedCourse.courseCode)
          .toList();

      for (var section in sectionsToRemove) {
        timetableService.removeSectionWithoutSaving(
          section.courseCode,
          section.sectionId,
          tt,
        );
      }

      // Add the replacement course (first available section of each type)
      final replacementSections = replacementCourse.sections;
      final lectureSection = replacementSections
              .where((s) => s.type == SectionType.L)
              .isNotEmpty
          ? replacementSections.firstWhere((s) => s.type == SectionType.L)
          : null;

      final tutorialSection = replacementSections
              .where((s) => s.type == SectionType.T)
              .isNotEmpty
          ? replacementSections.firstWhere((s) => s.type == SectionType.T)
          : null;

      final practicalSection = replacementSections
              .where((s) => s.type == SectionType.P)
              .isNotEmpty
          ? replacementSections.firstWhere((s) => s.type == SectionType.P)
          : null;

      // Add lecture section (required for most courses)
      if (lectureSection != null) {
        timetableService.addSectionWithoutSaving(
          replacementCourse.courseCode,
          lectureSection.sectionId,
          tt,
        );
      }

      // Add tutorial section if exists
      if (tutorialSection != null) {
        timetableService.addSectionWithoutSaving(
          replacementCourse.courseCode,
          tutorialSection.sectionId,
          tt,
        );
      }

      // Add practical section if exists
      if (practicalSection != null) {
        timetableService.addSectionWithoutSaving(
          replacementCourse.courseCode,
          practicalSection.sectionId,
          tt,
        );
      }

      setState(() {
        hasUnsavedChanges = true;
      });
      onUnsavedChangesChanged(true);

      ToastService.showSuccess(
        'Replaced ${selectedCourse.courseCode} with ${replacementCourse.courseCode}',
      );
    } catch (e) {
      showErrorDialog('Error replacing course: $e');
    }
  }

  Future<void> autoLoadCDCs() async {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      final autoLoadService = AutoLoadCDCService();
      final result = await autoLoadService.showBranchYearDialog(context);

      if (!mounted) return;

      if (result != null) {
        final selectedSections =
            await autoLoadService.loadCDCsForBranchAndSemester(
          branch: result.branch,
          semester: result.year,
          availableCourses: tt.availableCourses,
        );

        if (!mounted) return;

        if (selectedSections.isNotEmpty) {
          _pushUndo('Auto load CDCs');
          for (final selectedSection in selectedSections) {
            timetableService.addSectionWithoutSaving(
              selectedSection.courseCode,
              selectedSection.sectionId,
              tt,
            );
          }

          setState(() {
            hasUnsavedChanges = true;
          });
          onUnsavedChangesChanged(true);
          pageLeaveWarning.enableWarning(true);

          ToastService.showSuccess(
            'Auto-loaded ${selectedSections.length} CDC courses',
          );
        } else {
          ToastService.showInfo(
            'No CDC courses found for the selected branch and year',
          );
        }
      }
    } catch (e) {
      showErrorDialog('Error auto-loading CDCs: $e');
    }
  }

  Future<void> clearTimetable() async {
    final tt = currentTimetable;
    if (tt == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Timetable'),
        content: const Text(
          'Are you sure you want to remove all selected courses from your timetable?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        _pushUndo('Clear timetable');
        tt.selectedSections.clear();
        tt.clashWarnings.clear();
        setState(() {
          hasUnsavedChanges = true;
        });
        onUnsavedChangesChanged(true);
        pageLeaveWarning.enableWarning(true);

        ToastService.showSuccess('Timetable cleared successfully');
      } catch (e) {
        showErrorDialog('Error clearing timetable: $e');
      }
    }
  }

  Future<void> saveTimetable() async {
    final tt = currentTimetable;
    if (tt == null || isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      await timetableService.saveTimetable(tt);
      if (!mounted) return;
      setState(() {
        hasUnsavedChanges = false;
        isSaving = false;
      });
      onUnsavedChangesChanged(false);
      pageLeaveWarning.enableWarning(false);
      triggerSavedIndicator();

      ToastService.showSuccess('Timetable saved successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSaving = false;
      });
      showErrorDialog('Error saving timetable: $e');
    }
  }

  Future<void> shareTimetable() async {
    var tt = currentTimetable;
    if (tt == null) return;
    if (tt.selectedSections.isEmpty) {
      ToastService.showWarning('Add some courses before sharing');
      return;
    }

    // Assign a persistent shareId if this timetable doesn't have one yet
    if (tt.shareId == null) {
      final newId = TimetableSharingService().generateShareId();
      tt = tt.copyWith(shareId: () => newId);
      setState(() {
        _setCurrentTimetable(tt!);
      });
      await timetableService.saveTimetable(tt);
    }

    final returnedShareId = await ShareTimetableDialog.show(context, tt);
    // If revoked, the dialog returns a new shareId
    if (returnedShareId != null && returnedShareId != tt.shareId && mounted) {
      final updated = tt.copyWith(shareId: () => returnedShareId);
      setState(() {
        _setCurrentTimetable(updated);
      });
      await timetableService.saveTimetable(updated);
    }
  }

  void _setCurrentTimetable(Timetable tt);

  void showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  Future<bool> showIncompleteWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Incomplete Course Selections'),
            content: const Text(
              'Some courses have incomplete selections (missing lab/tutorial/lecture sections). Do you want to continue exporting anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> exportToICS() async {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToICS(
        tt.selectedSections,
        tt.availableCourses,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable exported to: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      showErrorDialog('Export failed: $e');
    }
  }

  Future<void> exportToPNG() async {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
      return;
    }

    // Check for incomplete course selections
    final warnings = timetableService.getIncompleteSelectionWarnings(
      tt.selectedSections,
      tt.availableCourses,
    );
    if (warnings.isNotEmpty) {
      final shouldContinue = await showIncompleteWarningDialog();
      if (!shouldContinue) {
        return;
      }
    }

    if (!mounted) return;

    // Show export options dialog
    final ExportOptions? exportOptions = await showDialog<ExportOptions>(
      context: context,
      builder: (context) => const ExportOptionsDialog(),
    );

    if (exportOptions == null) return; // User cancelled
    if (!mounted) return;

    try {
      GlobalKey tableExportKey = GlobalKey();

      final overlay = Overlay.of(context);
      late OverlayEntry overlayEntry;

      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: -10000,
          top: -10000,
          child: Material(
            child: SizedBox(
              width: 2000, // Provide enough width for full table
              height: 2000, // Provide enough height for full table
              child: TimetableWidget(
                timetableSlots: timetableService.generateTimetableSlots(
                  tt.selectedSections,
                  tt.availableCourses,
                ),
                incompleteSelectionWarnings:
                    timetableService.getIncompleteSelectionWarnings(
                  tt.selectedSections,
                  tt.availableCourses,
                ),
                size: TimetableSize
                    .extraLarge, // Use largest size for best quality
                isForExport: true,
                tableKey: tableExportKey,
                exportOptions: exportOptions,
              ),
            ),
          ),
        ),
      );

      overlay.insert(overlayEntry);

      // Wait for the widget to render
      await Future.delayed(const Duration(milliseconds: 500));

      final filePath = await ExportService.exportToPNG(tableExportKey);

      overlayEntry.remove();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable downloaded as: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      showErrorDialog('Export failed: $e');
    }
  }

  Future<void> openGenerator() async {
    final tt = currentTimetable;
    final result =
        await Navigator.push<List<timetable_models.SelectedSection>>(
      context,
      FadeSlidePageRoute(page: const GeneratorScreen()),
    );

    if (!mounted) return;

    if (result != null && tt != null) {
      try {
        _pushUndo('Apply generated timetable');
        // Clear current selections
        tt.selectedSections.clear();

        // Add new selections from generator
        for (final section in result) {
          await timetableService.addSection(
            section.courseCode,
            section.sectionId,
            tt,
          );
        }

        if (!mounted) return;
        setState(() {});

        ToastService.showSuccess('Generated timetable applied successfully!');
      } catch (e) {
        showErrorDialog('Error applying generated timetable: $e');
      }
    }
  }

  Future<void> openAddSwap() async {
    final tt = currentTimetable;
    if (tt == null) return;

    await Navigator.push(
      context,
      FadeSlidePageRoute(
        page: AddSwapScreen(
          currentSelectedSections: tt.selectedSections,
          availableCourses: tt.availableCourses,
          currentCampus: CampusService.currentCampusCode,
          onTimetableUpdated: (updatedSections) {
            setState(() {
              tt.selectedSections.clear();
              tt.selectedSections.addAll(updatedSections);
              hasUnsavedChanges = true;
            });
            onUnsavedChangesChanged(true);
            pageLeaveWarning.enableWarning(true);
          },
        ),
      ),
    );
  }

  Future<void> openGitHub() async {
    // Replace with your GitHub repository URL
    const String githubUrl = 'https://github.com/RCR0101/timetable_maker';

    try {
      // For web, open in new tab
      if (kIsWeb) {
        html.window.open(githubUrl, '_blank');
      } else {
        // For mobile, you'd need url_launcher package
        print('Open GitHub: $githubUrl');
      }
    } catch (e) {
      print('Error opening GitHub: $e');
    }
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        await authService.signOut();
        // Force navigation back to root since we're deep in navigation stack
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        showErrorDialog('Error signing out: $e');
      }
    }
  }
}
