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
import '../utils/course_utils.dart';
import '../services/ui/export_service.dart';
import '../services/ui/secure_logger.dart';
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
import '../widgets/app_destinations.dart';
import '../widgets/app_tools.dart';
import '../widgets/app_shell.dart';
import '../services/ui/tutorial_service.dart';
import '../widgets/campus_selector_widget.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../screens/generator_screen.dart';
import '../screens/add_swap_screen.dart';
import '../screens/quick_replace_screen.dart';
import '../widgets/exam_timeline_widget.dart';
import '../models/academic_record.dart';
import '../models/prerequisite_status.dart';
import '../models/timetable_selection_link.dart';
import '../repositories/prerequisites_repository.dart';
import '../services/data/academic_record_service.dart';
import '../utils/page_info_helper.dart';
import '../utils/route_utils.dart';

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

  /// Notifies the host that unsaved-changes state flipped. Hosts without a
  /// listener may implement this as a no-op.
  void onUnsavedChangesChanged(bool value);

  /// The single place an edit announces it has dirtied (or cleaned) the
  /// timetable. It arms *both* the host's back-guard prompt and the web
  /// refresh/close prompt at once, so no mutation path can flip one without the
  /// other — the cause of a refresh sneaking through with unsaved edits.
  void markUnsaved(bool value) {
    onUnsavedChangesChanged(value);
    pageLeaveWarning.enableWarning(value);
  }

  UserSettingsService get userSettingsService;

  // -- Shared filteredCourses state --
  List<Course> get filteredCourses;
  set filteredCourses(List<Course> value);

  // -- Undo/Redo --
  final UndoRedoService undoRedoService = UndoRedoService();

  // Wide-layout only: lets the user fold the left course panel away to a slim
  // rail so the grid can use the full width. Ephemeral (per editor session);
  // mobile uses tabs instead, so it's ignored there.
  bool _coursesCollapsed = false;

  // -- Selection broadcast --
  // Screens pushed on top of the editor (the elective browsers) hold the live
  // selectedSections list, so they only need a ping to know it changed. While
  // one of them is on top the only paths that can change the selection are
  // addSection and removeSection — including the exam-clash Override, which
  // re-enters addSection from a toast — so bumping there is sufficient.
  final ValueNotifier<int> _selectionRevision = ValueNotifier(0);

  /// Wires a pushed browser screen to the timetable being edited. Null when no
  /// timetable is open, which leaves those screens read-only.
  TimetableSelectionLink? get selectionLink {
    final tt = currentTimetable;
    if (tt == null) return null;
    return TimetableSelectionLink(
      selectedSections: tt.selectedSections,
      availableCourses: tt.availableCourses,
      onSectionToggle: (courseCode, sectionId, isSelected) {
        if (isSelected) {
          removeSection(courseCode, sectionId);
        } else {
          addSection(courseCode, sectionId);
        }
      },
      revision: _selectionRevision,
      timetableName: tt.name,
    );
  }

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
    markUnsaved(true);
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

  // -- Academic record --
  // Drives the "already cleared" markers in the course list and the
  // prerequisite warning below. Empty until loaded, and stays empty for anyone
  // who has never filled in the CGPA calculator.
  AcademicRecord _academicRecord = AcademicRecord.empty;
  AcademicRecord get academicRecord => _academicRecord;

  Future<void> _loadAcademicRecord() async {
    final record = await AcademicRecordService().load();
    if (mounted) setState(() => _academicRecord = record);
  }

  /// Flags — after the fact, never blocking — a newly added course whose
  /// prerequisites the student's record says are outstanding.
  ///
  /// Advice only, deliberately: the prerequisite data is incomplete for some
  /// courses, and a student may well have cleared something they never entered
  /// into the calculator. Refusing the add on that basis would be wrong.
  Future<void> _warnAboutPrerequisites(String courseCode) async {
    try {
      if (_academicRecord.isEmpty) return;
      final prereqs =
          await PrerequisitesRepository().getCoursePrerequisites(courseCode);
      if (prereqs == null || !mounted) return;

      final status = PrerequisiteStatus.of(prereqs, _academicRecord);
      if (status.isMet != false) return;

      ToastService.showWarning(
        '$courseCode normally needs '
        '${status.outstanding.map((p) => p.courseCode).join(', ')} first — '
        'check before you register.',
      );
    } catch (e) {
      SecureLogger.warning('EDITOR', 'Prerequisite check failed', {
        'courseCode': courseCode,
        'error': e.toString(),
      });
    }
  }

  // Cmd/Ctrl+K is handled at the keyboard level rather than via a focused
  // CallbackShortcuts, so it keeps working even after focus has drifted off the
  // editor subtree (dialogs, tab switches). The route-is-current guard means
  // only the topmost editor handles it — a pushed dialog or another route wins.
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalCommandPaletteKey);
    _loadAcademicRecord();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalCommandPaletteKey);
    _selectionRevision.dispose();
    super.dispose();
  }

  bool _handleGlobalCommandPaletteKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    _showCommandPalette();
    return true;
  }

  void _showCommandPalette() {
    CommandPalette.show(
      context,
      currentScreen: DrawerScreen.timetables,
      contextEntries: [
        CommandPaletteEntry(
          label: 'TT Generator',
          subtitle: 'Auto-generate optimal timetables',
          icon: Icons.auto_awesome_mosaic,
          category: CommandCategory.context,
          onSelect: openGenerator,
        ),
        CommandPaletteEntry(
          label: 'Add/Swap Courses',
          subtitle: 'Add a course or swap sections',
          icon: Icons.swap_horiz,
          category: CommandCategory.context,
          onSelect: openAddSwap,
        ),
        CommandPaletteEntry(
          label: 'Auto-load CDCs',
          subtitle: 'Add your compulsory disciplinary courses',
          icon: Icons.school,
          category: CommandCategory.context,
          onSelect: autoLoadCDCs,
        ),
        if ((currentTimetable?.selectedSections.isNotEmpty ?? false)) ...[
          CommandPaletteEntry(
            label: 'Quick Replace',
            subtitle: 'Swap a course for a similar one',
            icon: Icons.find_replace,
            category: CommandCategory.context,
            onSelect: openQuickReplace,
          ),
          CommandPaletteEntry(
            label: 'Clear Timetable',
            subtitle: 'Remove all courses from this timetable',
            icon: Icons.delete_sweep,
            category: CommandCategory.context,
            onSelect: clearTimetable,
          ),
        ],
        if (hasUnsavedChanges && !isSaving)
          CommandPaletteEntry(
            label: 'Save Timetable',
            subtitle: 'Save current changes',
            icon: Icons.save,
            category: CommandCategory.context,
            shortcut: '⌘S',
            onSelect: saveTimetable,
          ),
        if (undoRedoService.canUndo)
          CommandPaletteEntry(
            label: 'Undo',
            subtitle: undoRedoService.undoDescription ?? 'Undo last change',
            icon: Icons.undo,
            category: CommandCategory.context,
            shortcut: '⌘Z',
            onSelect: undo,
          ),
        if (undoRedoService.canRedo)
          CommandPaletteEntry(
            label: 'Redo',
            subtitle: undoRedoService.redoDescription ?? 'Redo last change',
            icon: Icons.redo,
            category: CommandCategory.context,
            shortcut: '⇧⌘Z',
            onSelect: redo,
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
      onNavigate: navigateToShellScreen,
      selectionLink: selectionLink,
      onToggleTheme: () => ThemeSelectorDialog.show(context),
      onReplayTour: () => TutorialService().showEditorTutorial(context, force: true),
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
        // Cmd/Ctrl+K is handled globally in _handleGlobalCommandPaletteKey so it
        // survives focus drifting off this subtree.
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

      courses = CourseUtils.searchCourses(courses, query);

      if (filters['courseCode'] != null &&
          filters['courseCode'].toString().isNotEmpty) {
        courses = CourseUtils.filterByCourseCode(
          courses,
          filters['courseCode'],
        );
      }

      if (filters['instructor'] != null &&
          filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(
          courses,
          filters['instructor'],
        );
      }

      courses = CourseUtils.filterByCredits(
        courses,
        filters['minCredits'],
        filters['maxCredits'],
      );

      if (filters['days'] != null &&
          (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }

      if (filters['hours'] != null &&
          (filters['hours'] as List<int>).isNotEmpty) {
        courses = CourseUtils.filterByHours(courses, filters['hours']);
      }

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

  /// Adds a section, explaining any refusal.
  ///
  /// When the only obstacle is an exam clash the toast offers an Override,
  /// which re-runs the add with [allowExamClash] set. Class-time clashes and
  /// duplicate section types are never overridable.
  void addSection(String courseCode, String sectionId, {bool allowExamClash = false}) {
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
      // Snapshot before the attempt, commit to the undo stack only on success —
      // a refused add must not leave a no-op entry for the user to undo.
      final sectionsBefore = List<SelectedSection>.of(tt.selectedSections);
      final result = timetableService.addSectionWithoutSaving(
        courseCode,
        sectionId,
        tt,
        allowExamClash: allowExamClash,
      );

      if (result.isAllowed) {
        undoRedoService.pushSections(
          sectionsBefore,
          allowExamClash
              ? 'Add $courseCode $sectionId (exam clash overridden)'
              : 'Add $courseCode $sectionId',
        );
        setState(() {
          hasUnsavedChanges = true;
        });
        markUnsaved(true);
        _selectionRevision.value++;
        if (isNewCourse) _warnAboutPrerequisites(courseCode);
        if (allowExamClash) {
          ToastService.showWarning(
            'Added $courseCode-$sectionId with an exam clash — you cannot sit both exams.',
          );
        }
      } else if (result.isOverridable) {
        ToastService.showError(
          result.message,
          actionLabel: 'Override',
          onAction: () => addSection(courseCode, sectionId, allowExamClash: true),
        );
      } else {
        ToastService.showError(result.message);
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
      markUnsaved(true);
      _selectionRevision.value++;
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
      markUnsaved(true);
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
      markUnsaved(true);

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
        final selectedSections = await autoLoadService.loadCDCsForDegree(
          primaryBranch: result.primaryBranch,
          secondaryBranch: result.secondaryBranch,
          semester: result.semester,
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
          markUnsaved(true);

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
        markUnsaved(true);

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
      markUnsaved(false);
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
      ToastService.showWarning('Add courses to your timetable before exporting.');
      return;
    }

    // Same conditional-export dialog the PNG export uses, so the calendar file
    // carries only the fields the user wants.
    final ExportOptions? exportOptions = await showDialog<ExportOptions>(
      context: context,
      builder: (context) => const ExportOptionsDialog(),
    );
    if (exportOptions == null) return; // User cancelled.
    if (!mounted) return;

    try {
      final filePath = await ExportService.exportToICS(
        tt.selectedSections,
        tt.availableCourses,
        timetableId: tt.id,
        calendarName: tt.name,
        campusId: tt.campus.code,
        options: exportOptions,
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
      ToastService.showWarning('Add courses to your timetable before exporting.');
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
            // Both axes are left unbounded so the grid, and the exam schedule
            // under it, size to content. A fixed capture width used to be
            // needed because the old grid's columns were a fixed size; now that
            // columns divide the available width, pinning it to 2000 px would
            // stretch a three-day timetable into three 600 px columns.
            child: UnconstrainedBox(
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

      final String filePath;
      try {
        // Wait for the offscreen widget to lay out and paint before capturing.
        await Future.delayed(const Duration(milliseconds: 500));
        filePath = await ExportService.exportToPNG(tableExportKey);
      } finally {
        // Always tear down the offscreen overlay — leaving it inserted on a
        // failed capture leaks a mounted timetable subtree.
        overlayEntry.remove();
      }

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
      SecureLogger.error('EXPORT', 'PNG export failed', e);
      showErrorDialog('Export failed: $e');
    }
  }

  /// Opens the Quick Replace flow for the current timetable. Mirrors the
  /// in-grid Quick Replace button so the action is also reachable from the
  /// command palette.
  void openQuickReplace() {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) return;
    Navigator.push(
      context,
      FadeSlidePageRoute(
        page: QuickReplaceScreen(
          availableCourses: tt.availableCourses,
          selectedSections: tt.selectedSections,
          onReplace: quickReplaceCourse,
          onSectionShuffle: sectionShuffle,
        ),
      ),
    );
  }

  /// Sends the user to one of the shell's drawer screens — Calendar, CGPA
  /// Calculator and the rest — from inside the editor.
  ///
  /// The editor is a pushed route, so those screens live on a sibling route
  /// rather than below this one; getting to them means leaving the editor
  /// first. Deferring the switch via [popThen] keeps the unsaved-changes
  /// prompt honest: back out of it and the shell stays exactly where it was
  /// rather than having silently moved underneath.
  void navigateToShellScreen(DrawerScreen screen) {
    popThen(context, () => AppShell.goTo(screen));
  }

  void openTool(AppTool tool) {
    Navigator.push(
      context,
      FadeSlidePageRoute(page: AppTools.of(tool).build(selectionLink)),
    );
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
            markUnsaved(true);
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

  /// Wraps [buildCoursesPanel] with a slim header carrying the collapse
  /// control, shown only in the wide two-pane layout.
  Widget _buildExpandedCoursesPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
          child: Row(
            children: [
              Text(
                'Courses',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Collapse courses panel',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _coursesCollapsed = true),
              ),
            ],
          ),
        ),
        Expanded(child: buildCoursesPanel()),
      ],
    );
  }

  /// The folded state of the course panel: a narrow rail that restores the full
  /// panel (tap the label or the chevron) while the grid spans the freed width.
  /// The two build actions live here too — on wide layouts they only otherwise
  /// dock under the open panel (buildFABs is null), so folding must not strand
  /// them.
  Widget _buildCollapsedCoursesRail() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 44,
          child: Column(
            children: [
              const SizedBox(height: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Expand courses panel',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _coursesCollapsed = false),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _coursesCollapsed = false),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'Courses',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 8, endIndent: 8),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Add / Swap',
                visualDensity: VisualDensity.compact,
                onPressed: openAddSwap,
              ),
              IconButton(
                icon: Icon(Icons.auto_awesome_mosaic, color: scheme.primary),
                tooltip: 'TT Generator',
                visualDensity: VisualDensity.compact,
                onPressed: openGenerator,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildCoursesPanel() {
    final tt = currentTimetable!;
    return Column(
      children: [
        SearchFilterWidget(key: TutorialKeys.courseSearch, onSearchChanged: onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: filteredCourses,
              selectedSections: tt.selectedSections,
              record: _academicRecord,
              projectCount: tt.projectCount,
              onProjectCountChanged: (count) {
                setState(() {
                  tt.projectCount = count;
                  hasUnsavedChanges = true;
                });
                markUnsaved(true);
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
        if (ResponsiveService.isDesktop(context)) _buildBuildActionsBar(),
      ],
    );
  }

  /// The two "build my timetable" actions, docked under the courses panel on
  /// wide layouts.
  ///
  /// They used to be Scaffold FABs, which put them over the bottom-right of the
  /// *grid* — and in fit-to-screen the grid fills its panel exactly, so there
  /// was no scrolling the Friday/Saturday cells out from under them. Docking
  /// here costs the grid nothing. Mobile keeps its floating button: the panels
  /// are tabs there, so a bar living in the Courses tab would be unreachable
  /// from the Timetable one.
  Widget _buildBuildActionsBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              key: TutorialKeys.addSwapFab,
              onPressed: openAddSwap,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Add/Swap'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              key: TutorialKeys.generatorFab,
              onPressed: openGenerator,
              icon: const Icon(Icons.auto_awesome_mosaic, size: 18),
              label: const Text('TT Generator'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
            ),
          ),
        ],
      ),
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
            key: TutorialKeys.timetableGrid,
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
      IconButton(
        key: TutorialKeys.commandPalette,
        icon: const Icon(Icons.search),
        onPressed: _showCommandPalette,
        tooltip: isMobileLayout ? 'Search actions' : 'Search actions  ·  ⌘K',
      ),
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
          key: TutorialKeys.campusSelector,
          confirmSwitch: () => confirmCampusSwitch(),
          onCampusChanged: onCampusChanged,
        ),
        IconButton(
          key: TutorialKeys.shareButton,
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
      // On mobile the Tools items are merged into the More (⋮) menu below, so
      // the app bar shows a single overflow instead of two.
      if (!isMobileLayout)
        PopupMenuButton<AppTool>(
          key: TutorialKeys.toolsMenu,
          icon: const Icon(Icons.menu_book),
          tooltip: 'Tools',
          onSelected: openTool,
          itemBuilder: (context) => [
            for (final info in AppTools.editorMenu)
              PopupMenuItem(
                value: info.tool,
                child: ListTile(
                  leading: Icon(info.icon),
                  title: Text(info.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      PopupMenuButton<String>(
        // On mobile this doubles as the Tools menu (see above), so the tour's
        // Tools spotlight targets it here.
        key: isMobileLayout ? TutorialKeys.toolsMenu : null,
        icon: const Icon(Icons.more_vert),
        tooltip: 'More',
        onSelected: (value) {
          // Tools share this menu on mobile; they're keyed by AppTool.name.
          final tool = AppTools.byName(value);
          if (tool != null) {
            openTool(tool);
            return;
          }
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
            for (final info in AppTools.editorMenu)
              PopupMenuItem(
                value: info.tool.name,
                child: ListTile(
                  leading: Icon(info.icon),
                  title: Text(info.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuDivider(),
          ],
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
      return LayoutBuilder(
        builder: (context, constraints) {
          // The open panel keeps its old ~1/3 share (floored so it stays usable
          // on narrower desktops); folded, it shrinks to a slim rail and the
          // grid — the only Expanded child — animates out to fill the gap.
          final third = constraints.maxWidth / 3;
          final expandedWidth = third < 300 ? 300.0 : third;
          const railWidth = 60.0;
          final collapsed = _coursesCollapsed;
          const duration = Duration(milliseconds: 260);
          const curve = Curves.easeInOutCubic;
          return Row(
            children: [
              AnimatedContainer(
                duration: duration,
                curve: curve,
                width: collapsed ? railWidth : expandedWidth,
                // Both the full panel and the rail stay laid out at the open
                // width and clipped to the animating frame, so nothing reflows
                // as the width changes. The two cross-fade over the *same*
                // duration/curve as the width, so the chevron and contents move
                // in step with the grid reclaiming the space rather than
                // snapping ahead of it.
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: expandedWidth,
                    maxWidth: expandedWidth,
                    child: Stack(
                      children: [
                        AnimatedOpacity(
                          opacity: collapsed ? 0 : 1,
                          duration: duration,
                          curve: curve,
                          child: IgnorePointer(
                            ignoring: collapsed,
                            child: _buildExpandedCoursesPanel(),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: railWidth,
                          child: AnimatedOpacity(
                            opacity: collapsed ? 1 : 0,
                            duration: duration,
                            curve: curve,
                            child: IgnorePointer(
                              ignoring: !collapsed,
                              child: _buildCollapsedCoursesRail(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: buildTimetablePanel()),
            ],
          );
        },
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
    // Wide layouts dock these under the courses panel instead — see
    // _buildBuildActionsBar for why they can't float over the grid.
    if (isWideScreen) return null;
    // A single FAB that opens a chooser, so two stacked FABs no longer occlude
    // the grid's bottom-right corner on small screens.
    return FloatingActionButton(
      key: TutorialKeys.generatorFab,
      onPressed: () => _showMobileBuildActions(context),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      tooltip: 'Build timetable',
      heroTag: 'build_actions',
      child: const Icon(Icons.add),
    );
  }

  /// Mobile chooser for the two primary build actions, replacing the pair of
  /// stacked FABs.
  void _showMobileBuildActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.auto_awesome_mosaic, color: scheme.primary),
              title: const Text('TT Generator'),
              subtitle: const Text('Auto-generate a clash-free timetable'),
              onTap: () {
                Navigator.pop(ctx);
                openGenerator();
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: scheme.secondary),
              title: const Text('Add / Swap Courses'),
              subtitle: const Text('Add a course or swap sections'),
              onTap: () {
                Navigator.pop(ctx);
                openAddSwap();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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

        markUnsaved(false);

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
      ToastService.showWarning('Add courses to your timetable before exporting.');
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
