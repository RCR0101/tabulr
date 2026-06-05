import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import '../utils/web_utils.dart' as web_utils;
import '../models/course.dart';
import '../utils/page_transitions.dart';
import '../models/timetable.dart';
import '../models/timetable.dart' as timetable_models;
import '../models/timetable_stats.dart';
import '../models/export_options.dart';
import '../services/core/timetable_service.dart';
import '../services/core/course_utils.dart';
import '../services/ui/export_service.dart';
import '../services/data/auth_service.dart';
import '../services/ui/toast_service.dart';
import '../services/data/auto_load_cdc_service.dart';
import '../widgets/auto_load_cdc_dialog.dart';
import '../services/data/campus_service.dart';
import '../services/ui/page_leave_warning_service.dart';
import '../services/data/timetable_sharing_service.dart';
import '../services/core/undo_redo_service.dart';
import '../services/core/clash_detector.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/user_settings_service.dart';
import '../utils/design_constants.dart';
import '../widgets/error_dialog.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/share_timetable_dialog.dart';
import '../widgets/courses_tab_widget.dart';
import '../widgets/clash_warnings_widget.dart';
import '../widgets/search_filter_widget.dart';
import '../widgets/theme_selector_widget.dart';
import '../widgets/command_palette.dart';
import '../widgets/app_drawer.dart';
import '../widgets/campus_selector_widget.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../screens/generator_screen.dart';
import '../screens/add_swap_screen.dart';
import '../widgets/exam_timeline_widget.dart';
import '../screens/course_guide_screen.dart';
import '../screens/discipline_electives_screen.dart';
import '../screens/humanities_electives_screen.dart';
import '../screens/prerequisites_screen.dart';
import '../utils/page_info_helper.dart';

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

  UserSettingsService get userSettingsService;

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

  void _showCommandPalette() {
    CommandPalette.show(
      context,
      currentScreen: DrawerScreen.timetables,
      contextEntries: [
        if (hasUnsavedChanges && !isSaving)
          CommandPaletteEntry(
            label: 'Save Timetable',
            subtitle: 'Save current changes',
            icon: Icons.save,
            category: CommandCategory.context,
            onSelect: saveTimetable,
          ),
        CommandPaletteEntry(
          label: 'Share Timetable',
          subtitle: 'Share via code',
          icon: Icons.share,
          category: CommandCategory.context,
          onSelect: shareTimetable,
        ),
        CommandPaletteEntry(
          label: 'Export as Image',
          subtitle: 'Save timetable as PNG',
          icon: Icons.image,
          category: CommandCategory.context,
          onSelect: exportToPNG,
        ),
        CommandPaletteEntry(
          label: 'Export to Calendar',
          subtitle: 'Save as .ics file',
          icon: Icons.calendar_today,
          category: CommandCategory.context,
          onSelect: exportToICS,
        ),
        CommandPaletteEntry(
          label: 'Export Timetable File',
          subtitle: 'Save as .tt file',
          icon: Icons.file_upload,
          category: CommandCategory.context,
          onSelect: exportToTTWithFilePicker,
        ),
        CommandPaletteEntry(
          label: 'Import Timetable File',
          subtitle: 'Load from .tt file',
          icon: Icons.file_download,
          category: CommandCategory.context,
          onSelect: importFromTT,
        ),
      ],
      onNavigate: (_) {},
      onToggleTheme: () => ThemeSelectorDialog.show(context),
      onSignOut: () => authService.signOut(),
    );
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
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _showCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _showCommandPalette,
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

  double _currentTotalCredits() {
    final tt = currentTimetable;
    if (tt == null) return 0;
    final selectedCodes = tt.selectedSections.map((s) => s.courseCode).toSet();
    double credits = 0;
    for (final code in selectedCodes) {
      final course = tt.availableCourses.cast<Course?>().firstWhere(
        (c) => c!.courseCode == code,
        orElse: () => null,
      );
      if (course != null) credits += course.totalCredits;
    }
    credits += tt.projectCount * 3;
    return credits;
  }

  void addSection(String courseCode, String sectionId) {
    final tt = currentTimetable;
    if (tt == null) return;

    final isNewCourse = !tt.selectedSections.any((s) => s.courseCode == courseCode);
    if (isNewCourse) {
      final course = tt.availableCourses.cast<Course?>().firstWhere(
        (c) => c!.courseCode == courseCode,
        orElse: () => null,
      );
      final addedCredits = course?.totalCredits ?? 0;
      if (_currentTotalCredits() + addedCredits > 25) {
        ToastService.showError('Adding this course would exceed the 25 credit limit');
        return;
      }
    }

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

  void sectionShuffle(List<SelectedSection> newSections) {
    final tt = currentTimetable;
    if (tt == null) return;

    try {
      _pushUndo('Section shuffle');
      // Replace all selected sections with the new set
      for (final section in tt.selectedSections.toList()) {
        timetableService.removeSectionWithoutSaving(
          section.courseCode, section.sectionId, tt,
        );
      }
      for (final section in newSections) {
        timetableService.addSectionWithoutSaving(
          section.courseCode, section.sectionId, tt,
        );
      }

      setState(() {
        hasUnsavedChanges = true;
      });
      onUnsavedChangesChanged(true);
      ToastService.showSuccess('Sections shuffled successfully');
    } catch (e) {
      showErrorDialog('Error shuffling sections: $e');
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
      final result = await showDialog<AutoLoadCDCResult>(
        context: context,
        builder: (context) => const AutoLoadCDCDialog(),
      );

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

    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Clear Timetable',
      message: 'Are you sure you want to remove all selected courses from your timetable?',
      confirmLabel: 'Clear All',
      isDangerous: true,
    );

    if (!mounted) return;

    if (confirmed) {
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
    final tt = currentTimetable;
    if (tt == null) return;
    if (tt.selectedSections.isEmpty) {
      ToastService.showWarning('Add some courses before sharing');
      return;
    }

    // Assign a persistent shareId if this timetable doesn't have one yet
    if (tt.shareId == null) {
      final newId = TimetableSharingService().generateShareId();
      final updated = tt.copyWith(shareId: () => newId);
      setCurrentTimetable(updated);
      setState(() {});
      await timetableService.saveTimetable(updated);
    }

    final current = currentTimetable!;
    if (!mounted) return;
    final returnedShareId = await ShareTimetableDialog.show(context, current);
    // If revoked, the dialog returns a new shareId
    if (returnedShareId != null && returnedShareId != current.shareId && mounted) {
      final updated = current.copyWith(shareId: () => returnedShareId);
      setCurrentTimetable(updated);
      setState(() {});
      await timetableService.saveTimetable(updated);
    }
  }

  void setCurrentTimetable(Timetable tt);

  void showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  Future<bool> showIncompleteWarningDialog() async {
    return await AppDialog.confirm(
      context: context,
      title: 'Incomplete Course Selections',
      message: 'Some courses have incomplete selections (missing lab/tutorial/lecture sections). Do you want to continue exporting anyway?',
      confirmLabel: 'Continue',
      icon: Icons.warning_amber_rounded,
    );
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

      AppDialog.adaptive(
        context: context,
        title: 'Export Successful',
        icon: Icons.check_circle_outline,
        content: Text('Timetable exported to: $filePath'),
        actions: [
          AppButton(
            label: 'OK',
            onTap: () => Navigator.pop(context),
          ),
        ],
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
              width: 2000,
              height: 2200,
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
                selectedSections: tt.selectedSections,
                availableCourses: tt.availableCourses,
                size: TimetableSize
                    .extraLarge,
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

      AppDialog.adaptive(
        context: context,
        title: 'Export Successful',
        icon: Icons.check_circle_outline,
        content: Text('Timetable downloaded as: $filePath'),
        actions: [
          AppButton(
            label: 'OK',
            onTap: () => Navigator.pop(context),
          ),
        ],
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

  // ---------------------------------------------------------------------------
  // Saved indicator
  // ---------------------------------------------------------------------------
  bool _showSavedIndicator = false;
  bool get showSavedIndicator => _showSavedIndicator;
  Timer? _savedIndicatorTimer;

  void triggerSavedIndicator() {
    _savedIndicatorTimer?.cancel();
    setState(() => _showSavedIndicator = true);
    _savedIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSavedIndicator = false);
    });
  }

  void disposeSavedIndicator() {
    _savedIndicatorTimer?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  void initializeUserSettings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      userSettingsService.initializeSettings();
    });
  }

  Future<bool> confirmCampusSwitch() async {
    if (!hasUnsavedChanges) return true;
    return await AppDialog.confirm(
      context: context,
      title: 'Unsaved Changes',
      message: 'Switching campus will discard your unsaved changes. Continue?',
      confirmLabel: 'Switch',
      isDangerous: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Shared UI builders
  // ---------------------------------------------------------------------------

  Widget buildCoursesPanel() {
    final tt = currentTimetable!;
    return Column(
      children: [
        SearchFilterWidget(onSearchChanged: onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: filteredCourses,
              selectedSections: tt.selectedSections,
              projectCount: tt.projectCount,
              onProjectCountChanged: (count) {
                setState(() {
                  tt.projectCount = count;
                  hasUnsavedChanges = true;
                });
                onUnsavedChangesChanged(true);
              },
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  removeSection(courseCode, sectionId);
                } else {
                  addSection(courseCode, sectionId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget buildTimetablePanel() {
    final tt = currentTimetable!;
    final isMobile =
        ResponsiveService.isMobile(context) ||
        ResponsiveService.isTablet(context);
    return Column(
      children: [
        if (tt.clashWarnings.isNotEmpty)
          Card(
            margin: EdgeInsets.all(isMobile ? 4 : 8),
            child: ClashWarningsWidget(warnings: tt.clashWarnings),
          ),
        Expanded(
          child: Card(
            margin: EdgeInsets.all(isMobile ? 4 : 8),
            child: RepaintBoundary(
              key: timetableKey,
              child: TimetableWidget(
                timetableSlots: timetableService.generateTimetableSlots(
                  tt.selectedSections,
                  tt.availableCourses,
                ),
                incompleteSelectionWarnings: timetableService
                    .getIncompleteSelectionWarnings(
                      tt.selectedSections,
                      tt.availableCourses,
                    ),
                onClear: clearTimetable,
                onRemoveSection: removeSection,
                size: userSettingsService.getTimetableSize(tt.id),
                hasUnsavedChanges: hasUnsavedChanges,
                isSaving: isSaving,
                onSave: authService.isGuest ? null : saveTimetable,
                onAutoLoadCDCs: autoLoadCDCs,
                onSizeChanged: (newSize) {
                  userSettingsService.updateTimetableSettings(
                    tt.id,
                    newSize,
                    null,
                  );
                },
                layout: userSettingsService.getTimetableLayout(tt.id),
                onLayoutChanged: (newLayout) {
                  userSettingsService.updateTimetableSettings(
                    tt.id,
                    null,
                    newLayout,
                  );
                },
                availableCourses: tt.availableCourses,
                selectedSections: tt.selectedSections,
                onQuickReplace: quickReplaceCourse,
                onSectionShuffle: sectionShuffle,
                onUndo: undo,
                onRedo: redo,
                canUndo: undoRedoService.canUndo,
                canRedo: undoRedoService.canRedo,
                onShowStats: () => _showStatsSheet(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _dayLabel(DayOfWeek day) => switch (day) {
    DayOfWeek.M => 'Mon',
    DayOfWeek.T => 'Tue',
    DayOfWeek.W => 'Wed',
    DayOfWeek.Th => 'Thu',
    DayOfWeek.F => 'Fri',
    DayOfWeek.S => 'Sat',
  };

  void _showStatsSheet(BuildContext context) {
    final tt = currentTimetable;
    if (tt == null) return;
    final stats = TimetableStats.fromTimetable(tt);
    final scheme = Theme.of(context).colorScheme;

    Widget statsContent(BuildContext ctx) {
      final labelStyle = Theme.of(ctx).textTheme.labelSmall?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.6),
      );
      final valueStyle = Theme.of(ctx).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      );

      Widget statTile(IconData icon, String value, String label) {
        return Column(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 4),
            Text(value, style: valueStyle),
            Text(label, style: labelStyle),
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                statTile(Icons.schedule, '${stats.totalHoursPerWeek}', 'hrs/wk'),
                statTile(Icons.trending_up, '${_dayLabel(stats.busiestDay)} (${stats.busiestDayHours}h)', 'busiest'),
                statTile(Icons.event_available, '${stats.freeDayCount}', 'free days'),
                if (stats.longestGapHours > 0)
                  statTile(Icons.hourglass_empty, '${stats.longestGapHours}h', 'gap ${_dayLabel(stats.longestGapDay!)}'),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(child: ExamTimelineWidget(timetable: tt)),
        ],
      );
    }

    final isMobile = ResponsiveService.isMobile(context);
    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Timetable Stats', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(child: statsContent(ctx)),
            ],
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Text('Timetable Stats', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                Flexible(child: statsContent(ctx)),
              ],
            ),
          ),
        ),
      );
    }
  }

  List<Widget> buildCommonActions() {
    final isMobileLayout = ResponsiveService.isMobile(context);
    return [
      if (!isMobileLayout) ...[
        PageInfoHelper.infoButton(context, PageInfoHelper.timetableCreator),
        if (_showSavedIndicator)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppDesign.success(context), size: 18),
                const SizedBox(width: 4),
                Text('Saved', style: TextStyle(color: AppDesign.success(context), fontSize: 13)),
              ],
            ),
          ),
        CampusSelectorWidget(
          confirmSwitch: () => confirmCampusSwitch(),
          onCampusChanged: onCampusChanged,
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: shareTimetable,
          tooltip: 'Share Timetable',
        ),
        const ThemeToggleButton(),
      ],
      if (isMobileLayout && _showSavedIndicator)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.check_circle, color: AppDesign.success(context), size: 18),
        ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.menu_book),
        tooltip: 'Tools',
        onSelected: (value) {
          switch (value) {
            case 'course_guide':
              Navigator.push(context, FadeSlidePageRoute(page: const CourseGuideScreen()));
              break;
            case 'prerequisites':
              Navigator.push(context, FadeSlidePageRoute(page: const PrerequisitesScreen()));
              break;
            case 'discipline_electives':
              Navigator.push(context, FadeSlidePageRoute(page: const DisciplineElectivesScreen()));
              break;
            case 'humanities_electives':
              Navigator.push(context, FadeSlidePageRoute(page: const HumanitiesElectivesScreen()));
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'course_guide',
            child: ListTile(
              leading: Icon(Icons.menu_book),
              title: Text('Course Guide'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'prerequisites',
            child: ListTile(
              leading: Icon(Icons.account_tree),
              title: Text('Prerequisites'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'discipline_electives',
            child: ListTile(
              leading: Icon(Icons.school),
              title: Text('Discipline Electives'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'humanities_electives',
            child: ListTile(
              leading: Icon(Icons.library_books),
              title: Text('Humanities Electives'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'More',
        onSelected: (value) {
          switch (value) {
            case 'share': shareTimetable(); break;
            case 'page_info': PageInfoHelper.show(context, PageInfoHelper.timetableCreator); break;
            case 'import_tt': importFromTT(); break;
            case 'export_tt': exportToTTWithFilePicker(); break;
            case 'export_ics': exportToICS(); break;
            case 'export_png': exportToPNG(); break;
            case 'github': openGitHub(); break;
          }
        },
        itemBuilder: (context) => [
          if (isMobileLayout) ...[
            const PopupMenuItem(
              value: 'share',
              child: ListTile(
                leading: Icon(Icons.share),
                title: Text('Share Timetable'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'page_info',
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('About This Page'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuDivider(),
          ],
          const PopupMenuItem(
            value: 'import_tt',
            child: ListTile(
              leading: Icon(Icons.file_download),
              title: Text('Import Timetable (.tt)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'export_tt',
            child: ListTile(
              leading: Icon(Icons.file_upload),
              title: Text('Export Timetable (.tt)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'export_ics',
            child: ListTile(
              leading: Icon(Icons.calendar_today),
              title: Text('Export to Calendar (.ics)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'export_png',
            child: ListTile(
              leading: Icon(Icons.image),
              title: Text('Export as Image (.png)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'github',
            child: ListTile(
              leading: Icon(Icons.star_border),
              title: Text('Star on GitHub'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      if (authService.isAuthenticated)
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'logout') logout();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authService.userName ?? 'User',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    authService.userEmail ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const Divider(),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('Sign Out'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: authService.userPhotoUrl != null
                      ? authService.userPhotoImage
                      : null,
                  child: authService.userPhotoUrl == null
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                'Guest',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(width: 8),
    ];
  }

  Widget buildBodyLayout(bool isWideScreen) {
    if (isWideScreen) {
      return Row(
        children: [
          Expanded(flex: 1, child: buildCoursesPanel()),
          Expanded(flex: 2, child: buildTimetablePanel()),
        ],
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.search), text: 'Courses'),
                Tab(icon: Icon(Icons.calendar_view_week), text: 'Timetable'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                buildCoursesPanel(),
                buildTimetablePanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? buildFABs(bool isWideScreen) {
    if (isWideScreen) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: openAddSwap,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Add/Swap'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
            heroTag: 'add_swap',
          ),
          const SizedBox(width: 8),
          FloatingActionButton.extended(
            onPressed: openGenerator,
            icon: const Icon(Icons.auto_awesome_mosaic),
            label: const Text('TT Generator'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            heroTag: 'generator',
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          onPressed: openAddSwap,
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
          tooltip: 'Add/Swap Courses',
          heroTag: 'add_swap',
          child: const Icon(Icons.swap_horiz),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          onPressed: openGenerator,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          tooltip: 'TT Generator',
          heroTag: 'generator',
          child: const Icon(Icons.auto_awesome_mosaic),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Import / Export
  // ---------------------------------------------------------------------------

  void onCampusChanged(Campus campus);

  Future<void> importFromTT() async {
    try {
      final importedTimetable = await ExportService.importFromTTWithFilePicker();
      if (importedTimetable == null || !mounted) return;

      final shouldReplace = await AppDialog.confirm(
        context: context,
        title: 'Import Timetable',
        message: 'Are you sure you want to import "${importedTimetable.name}"?\n\n'
            'This will replace your current timetable with the imported one.\n\n'
            'Campus: ${importedTimetable.campus.toString().split('.').last}\n'
            'Courses: ${importedTimetable.selectedSections.length} sections',
        confirmLabel: 'Import',
      );

      if (shouldReplace) {
        if (CampusService.currentCampus != importedTimetable.campus) {
          await CampusService.setCampus(importedTimetable.campus);
        }
        final reloadedTimetable = await timetableService.loadTimetable();
        final clashWarnings = ClashDetector.detectClashes(
          importedTimetable.selectedSections,
          reloadedTimetable.availableCourses,
        );

        final updatedImportedTimetable = Timetable(
          id: importedTimetable.id,
          name: importedTimetable.name,
          createdAt: importedTimetable.createdAt,
          updatedAt: importedTimetable.updatedAt,
          campus: importedTimetable.campus,
          availableCourses: reloadedTimetable.availableCourses,
          selectedSections: importedTimetable.selectedSections,
          clashWarnings: clashWarnings,
        );

        await timetableService.saveTimetable(updatedImportedTimetable);

        setState(() {
          setCurrentTimetable(updatedImportedTimetable);
          filteredCourses = updatedImportedTimetable.availableCourses;
          hasUnsavedChanges = false;
        });

        pageLeaveWarning.enableWarning(false);
        onUnsavedChangesChanged(false);

        if (!mounted) return;
        ToastService.showSuccess(
          'Timetable "${importedTimetable.name}" imported successfully!',
        );
      }
    } catch (e) {
      showErrorDialog('Import failed: $e');
    }
  }

  Future<void> exportToTTWithFilePicker() async {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToTTWithFilePicker(tt);
      if (!mounted) return;
      AppDialog.adaptive(
        context: context,
        title: 'Export Successful',
        icon: Icons.check_circle_outline,
        content: Text('Timetable exported to: $filePath'),
        actions: [
          AppButton(
            label: 'OK',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      showErrorDialog('Export failed: $e');
    }
  }

  Future<void> openGitHub() async {
    const String githubUrl = AppUrls.githubRepo;

    try {
      if (kIsWeb) {
        web_utils.openUrl(githubUrl);
      } else {
        await launchUrl(Uri.parse(githubUrl));
      }
    } catch (e) {
      // Silently ignore URL launch errors
    }
  }

  Future<void> logout() async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      isDangerous: true,
    );

    if (!mounted) return;

    if (confirmed) {
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
