import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../models/course.dart';
import '../models/timetable.dart';
import '../models/timetable.dart' as timetable_models;
import '../models/export_options.dart';
import '../services/timetable_service.dart';
import '../services/course_utils.dart';
import '../services/export_service.dart';
import '../services/clash_detector.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../services/auto_load_cdc_service.dart';
import '../services/campus_service.dart';
import '../services/page_leave_warning_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/export_options_dialog.dart';
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
        final course = tt.availableCourses.firstWhere(
          (c) => c.courseCode == courseCode,
        );
        final section = course.sections.firstWhere(
          (s) => s.sectionId == sectionId,
        );

        // Check specific reason for failure
        final existingSameType = tt.selectedSections.where(
          (s) => s.courseCode == courseCode && s.section.type == section.type,
        );

        if (existingSameType.isNotEmpty) {
          showErrorDialog(
            'You can only select one ${section.type.name} section per course.\nAlready selected: ${existingSameType.first.sectionId}',
          );
        } else {
          showErrorDialog(
            'Cannot add section due to time conflicts or exam clashes',
          );
        }
      }
    } catch (e) {
      showErrorDialog('Error adding section: $e');
    }
  }

  void removeSection(String courseCode, String sectionId) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      final removedSection = tt.selectedSections.firstWhere(
        (s) => s.courseCode == courseCode && s.sectionId == sectionId,
      );

      timetableService.removeSectionWithoutSaving(
        courseCode,
        sectionId,
        tt,
      );
      setState(() {
        hasUnsavedChanges = true;
      });
      onUnsavedChangesChanged(true);

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $courseCode $sectionId'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                tt.selectedSections.add(removedSection);
                tt.clashWarnings
                  ..clear()
                  ..addAll(ClashDetector.detectClashes(
                    tt.selectedSections,
                    tt.availableCourses,
                  ));
              });
            },
          ),
        ),
      );
    } catch (e) {
      showErrorDialog('Error removing section: $e');
    }
  }

  void quickReplaceCourse(Course selectedCourse, Course replacementCourse) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
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

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Replaced ${selectedCourse.courseCode} with ${replacementCourse.courseCode}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
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
      MaterialPageRoute(builder: (context) => const GeneratorScreen()),
    );

    if (!mounted) return;

    if (result != null && tt != null) {
      try {
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
      MaterialPageRoute(
        builder: (context) => AddSwapScreen(
          currentSelectedSections: tt.selectedSections,
          availableCourses: tt.availableCourses,
          currentCampus: CampusService.currentCampusCode,
          onTimetableUpdated: (updatedSections) {
            // Update the main timetable with the new sections
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
