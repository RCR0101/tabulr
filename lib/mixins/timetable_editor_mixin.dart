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
import '../models/credit_mix.dart';
import '../models/elective_pool.dart';
import '../models/export_options.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/profile_service.dart';
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
import '../services/ui/theme_service.dart';
import '../services/data/user_settings_service.dart';
import '../utils/design_constants.dart';
import '../widgets/error_dialog.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/share_timetable_dialog.dart';
import '../widgets/courses_tab_widget.dart';
import '../widgets/credit_basis_notice.dart';
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
import '../widgets/timetable_stats_panel.dart';
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

  // -- Clash / credit bypasses --
  // Switches from the grid toolbar's settings menu. Each turns on freely;
  // turning one off is refused while the grid still carries the violation it
  // allowed, so the menu can never claim "no clashes" over a grid that visibly
  // has one.
  //
  // Only the user's explicit "on" is session state. Whether a bypass *reads* as
  // on is derived below, because the timetable is the real record: a clash
  // saved to one is still there after a reload, and a switch that reset itself
  // to off would claim otherwise — and then refuse the next matching add.
  bool _allowExamClash = false;
  bool _allowSectionClash = false;
  bool _allowCreditBypass = false;

  bool get allowExamClash => _allowExamClash || _hasExamClash;
  bool get allowSectionClash => _allowSectionClash || _hasSectionClash;
  bool get allowCreditBypass => _allowCreditBypass || _isOverCreditCap;

  /// Clashes currently on the grid, however they got there (an active bypass
  /// or a timetable loaded with one already in it).
  List<ClashWarning> _currentClashes() {
    final tt = currentTimetable;
    if (tt == null) return const [];
    return ClashDetector.detectClashes(
      tt.selectedSections,
      tt.availableCourses,
    );
  }

  bool get _hasExamClash => _currentClashes().any(
    (w) => w.type == ClashType.midSemExam || w.type == ClashType.endSemExam,
  );
  bool get _hasSectionClash =>
      _currentClashes().any((w) => w.type == ClashType.regularClass);
  bool get _isOverCreditCap => _currentTotalCredits() > capFor(creditBasis);

  bool setBypassAllowed(TimetableBypass bypass, bool allowed) {
    if (!allowed) {
      final String? refusal = switch (bypass) {
        TimetableBypass.examClash =>
          _hasExamClash
              ? 'An exam clash is still on the grid — remove one of the clashing courses first.'
              : null,
        TimetableBypass.sectionClash =>
          _hasSectionClash
              ? 'A section clash is still on the grid — remove one of the clashing sections first.'
              : null,
        TimetableBypass.creditLimit =>
          _isOverCreditCap
              ? 'Still over the ${capFor(creditBasis).toInt()} ${creditBasis.label} limit — remove a course first.'
              : null,
      };
      if (refusal != null) {
        ToastService.showError(refusal);
        return false;
      }
    }
    setState(() {
      switch (bypass) {
        case TimetableBypass.examClash:
          _allowExamClash = allowed;
        case TimetableBypass.sectionClash:
          _allowSectionClash = allowed;
        case TimetableBypass.creditLimit:
          _allowCreditBypass = allowed;
      }
    });
    return true;
  }

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
      creditBasis: tt.creditBasis,
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
      final prereqs = await PrerequisitesRepository().getCoursePrerequisites(
        courseCode,
      );
      if (prereqs == null || !mounted) return;

      final status = PrerequisiteStatus.of(prereqs, _academicRecord);
      if (status.isMet != false) return;

      ToastService.showWarning(
        '$courseCode normally needs '
        '${status.outstanding.map((g) => g.label).join(', ')} first — '
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
    loadElectivePools();
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
      onReplayTour:
          () => TutorialService().showEditorTutorial(context, force: true),
      onSignOut: () => authService.signOut(),
    );
  }

  Widget wrapWithKeyboardShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
        const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ):
            redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (hasUnsavedChanges && !isSaving) saveTimetable();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (hasUnsavedChanges && !isSaving) saveTimetable();
        },
        // Cmd/Ctrl+K is handled globally in _handleGlobalCommandPaletteKey so it
        // survives focus drifting off this subtree.
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  // -----------------------------------------------------------------------
  // Shared methods
  // -----------------------------------------------------------------------

  /// DEL/HUEL/CDC membership for the student's own branch, resolved once.
  ///
  /// The search filter runs synchronously on every keystroke, so the async
  /// lookup happens here instead of inside it — [BranchStructureService] caches,
  /// but the filter cannot await regardless.
  ElectivePools _electivePools = ElectivePools.empty;

  /// Whether the elective-type chips are worth offering. Reads the profile
  /// rather than the pools so the chips appear immediately, before the branch
  /// data has come back.
  bool get hasBranchForPools =>
      (ProfileService().cached.primaryBranch ?? '').isNotEmpty;

  /// Loads the pools in the background. Safe to call more than once; a failure
  /// leaves [ElectivePools.empty], which the filter reads as "classify nothing"
  /// and passes every course through.
  Future<void> loadElectivePools() async {
    final profile = ProfileService().cached;
    if (!hasBranchForPools || !_electivePools.isEmpty) return;
    try {
      final pools = await BranchStructureService().electivePoolsFor([
        profile.primaryBranch,
        profile.secondaryBranch,
      ]);
      if (mounted) setState(() => _electivePools = pools);
    } catch (e) {
      SecureLogger.warning(
        'EDITOR',
        'Could not resolve elective pools (filter stays open)',
        {'error': e.toString()},
      );
    }
  }

  void onSearchChanged(String query, Map<String, dynamic> filters) {
    final tt = currentTimetable;
    if (tt == null) return;

    setState(() {
      var courses = tt.availableCourses;

      courses = CourseUtils.searchCourses(courses, query);

      // A course with no sections cannot be added to anything, so it is hidden
      // unless explicitly asked for in the advanced filters.
      if (filters['includeSectionless'] != true) {
        courses = CourseUtils.filterOutSectionless(courses);
      }

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

      // Elective type. Skipped entirely when the pools never resolved, so a
      // branch lookup that failed narrows the list to nothing rather than
      // hiding the whole catalogue behind a chip the student did press.
      final pools = filters['electivePools'] as Set<ElectivePool>? ?? const {};
      if (pools.isNotEmpty && !_electivePools.isEmpty) {
        courses =
            courses
                .where((c) => _electivePools.matchesAny(pools, c.courseCode))
                .toList();
      }

      filteredCourses = courses;
    });
  }

  /// What this timetable counts in — units unless it was switched.
  CreditBasis get creditBasis =>
      currentTimetable?.creditBasis ?? CreditBasis.units;

  /// Only the courses that can be taken on this timetable's basis.
  ///
  /// Filtering the list rather than refusing at Add: a credit-hours student
  /// scrolling past courses they cannot register for is a worse experience
  /// than a shorter list, and the refusal below only exists for the paths that
  /// bypass this list (deep links, quick replace, imports).
  List<Course> get coursesInBasis =>
      filteredCourses.where((c) => c.offersBasis(creditBasis)).toList();

  /// Switches the whole timetable between units and contact hours.
  ///
  /// Refuses while courses of the other basis are still on the grid — silently
  /// dropping a student's work to satisfy a toggle is not a trade this makes.
  void setCreditBasis(CreditBasis basis) {
    final tt = currentTimetable;
    if (tt == null || tt.creditBasis == basis) return;

    // A course printed both ways just changes which row it is registered under;
    // one printed only the other way cannot come along, and dropping it
    // silently to satisfy a toggle is not a trade this makes.
    final byCode = {for (final c in tt.availableCourses) c.courseCode: c};
    final stranded = <String>{
      for (final s in tt.selectedSections)
        if (!(byCode[s.courseCode]?.offersBasis(basis) ?? false)) s.courseCode,
    };
    if (stranded.isNotEmpty) {
      ToastService.showError(
        'Remove ${stranded.length} course${stranded.length == 1 ? '' : 's'} first — '
        '${stranded.take(3).join(', ')}${stranded.length > 3 ? '…' : ''} '
        '${stranded.length == 1 ? 'is' : 'are'} not offered in ${basis.label}.',
      );
      return;
    }

    _pushUndo('Switch to ${basis.label}');
    setState(() {
      _restateOn(tt, basis);
      hasUnsavedChanges = true;
    });
    markUnsaved(true);
    _selectionRevision.value++;
  }

  /// Puts [tt] on [basis] and re-registers every selection under that basis's
  /// com cod, so the grid, the credits bar and the cap all read the same
  /// quantity. Leaving the old com cods behind is what makes a timetable report
  /// one basis while counting in the other.
  ///
  /// Assumes the caller has already established that nothing on the grid is
  /// stranded off [basis] — [setCreditBasis] checks, and the generator apply
  /// path is replacing the whole selection anyway.
  void _restateOn(Timetable tt, CreditBasis basis) {
    final byCode = {for (final c in tt.availableCourses) c.courseCode: c};
    tt.creditBasis = basis;
    for (var i = 0; i < tt.selectedSections.length; i++) {
      final sel = tt.selectedSections[i];
      final comCode = byCode[sel.courseCode]?.variantOn(basis)?.comCode;
      tt.selectedSections[i] = sel.withComCode(comCode);
    }
  }

  /// What this timetable currently counts in, and whether it is coherent.
  CreditMix get creditMix {
    final tt = currentTimetable;
    if (tt == null) return CreditMix.empty;
    return CreditMix.of(tt.selectedSections, tt.availableCourses);
  }

  /// The timetable's load on its own basis, which is the only figure its cap
  /// can be checked against.
  ///
  /// Reading units off a credit-hours timetable reports 0 — its courses have no
  /// unit count — so every check downstream compared 0 to the 70-hour ceiling
  /// and never refused anything.
  double _currentTotalCredits() {
    final tt = currentTimetable;
    if (tt == null) return 0;
    final basis = creditBasis;
    final credits = creditMix.amountFor(basis);
    // A project is worth 3 units and the booklet prints no hours figure for
    // one, so it counts toward a unit total only — converting it would be
    // inventing the number this model exists to avoid inventing.
    return basis == CreditBasis.units ? credits + tt.projectCount * 3 : credits;
  }

  /// Drops every course counted in [basis] — the escape hatch from a timetable
  /// holding both units and credit hours.
  Future<void> removeAllInBasis(CreditBasis basis) async {
    final tt = currentTimetable;
    if (tt == null) return;
    final codes = creditMix.coursesFor(basis).toSet();
    if (codes.isEmpty) return;

    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Remove ${basis.label} courses',
      message:
          codes.length == 1
              ? 'Remove ${codes.first} from this timetable?'
              : 'Remove all ${codes.length} courses counted in ${basis.label}?\n\n'
                  '${codes.join(', ')}',
      confirmLabel: 'Remove',
      isDangerous: true,
    );
    if (!mounted || !confirmed) return;

    _pushUndo('Remove all ${basis.label} courses');
    tt.selectedSections.removeWhere((s) => codes.contains(s.courseCode));
    tt.clashWarnings.clear();
    setState(() {
      hasUnsavedChanges = true;
    });
    markUnsaved(true);
    _selectionRevision.value++;
    ToastService.showSuccess(
      'Removed ${codes.length} ${basis.label} course${codes.length == 1 ? '' : 's'}',
    );
  }

  /// Adds a section, explaining any refusal.
  ///
  /// When the only obstacle is an exam clash the toast offers an Override,
  /// which re-runs the add with [overrideExamClash] set for that one add. The
  /// toolbar's bypass switches ([allowExamClash], [allowSectionClash],
  /// [allowCreditBypass]) pre-authorize the same obstacles for every add.
  /// Duplicate section types are never overridable.
  void addSection(
    String courseCode,
    String sectionId, {
    bool overrideExamClash = false,
    int? comCode,
  }) {
    final tt = currentTimetable;
    if (tt == null) return;

    // Read the bypasses once, before the add: they derive partly from the
    // clashes already on the grid, so re-reading them afterwards would report
    // this add's own clash as having pre-authorized it.
    final examClashAllowed = overrideExamClash || allowExamClash;
    final sectionClashAllowed = allowSectionClash;

    final isNewCourse =
        !tt.selectedSections.any((s) => s.courseCode == courseCode);
    final course = tt.availableCourses.cast<Course?>().firstWhere(
      (c) => c!.courseCode == courseCode,
      orElse: () => null,
    );
    // A course already on the grid keeps the basis it was added under, so a
    // second section of it cannot silently switch the course to the other one.
    // The timetable's basis picks the row to register under, so a course
    // offered both ways lands on the same footing as everything else on the
    // grid without the student choosing twice.
    final basisCode =
        isNewCourse
            ? (comCode ?? course?.variantOn(creditBasis)?.comCode)
            : tt.selectedSections
                .firstWhere((s) => s.courseCode == courseCode)
                .comCode;
    final variant = course?.variantFor(basisCode);

    // A course the student cannot register for on this timetable's basis is
    // refused here rather than silently counted as zero. The course list is
    // already filtered, so this catches the ways in that bypass it: quick
    // replace, a shared link, an import, a deep link from the professor screen.
    if (isNewCourse && course != null && !course.offersBasis(creditBasis)) {
      ToastService.showError(
        '$courseCode is not offered in ${creditBasis.label} — '
        'this timetable counts in ${creditBasis.label}.',
      );
      return;
    }

    // Each basis is checked against its own ceiling: 25 units, or 70 contact
    // hours for a 2026-batch timetable. Measuring one against the other's cap
    // either refuses a second course for the whole batch or refuses nothing.
    final cap = capFor(creditBasis);
    if (isNewCourse && !allowCreditBypass) {
      final addedCredits = variant?.amount ?? 0;
      if (_currentTotalCredits() + addedCredits > cap) {
        ToastService.showError(
          'Adding this course would exceed the ${cap.toInt()} ${creditBasis.label} limit',
        );
        return;
      }
    }

    // Adding a second L (or T, or P) of a course already on the grid means
    // switching to it — the course card offers exactly that button. Handled
    // here rather than in the card so every other way in (the elective
    // browsers, the command palette) means the same thing instead of being
    // refused for a duplicate section type.
    final incoming = course?.sections.cast<Section?>().firstWhere(
      (s) => s!.sectionId == sectionId,
      orElse: () => null,
    );
    final replaced =
        incoming == null
            ? null
            : tt.selectedSections.cast<SelectedSection?>().firstWhere(
              (s) =>
                  s!.courseCode == courseCode &&
                  s.section.type == incoming.type &&
                  s.sectionId != sectionId,
              orElse: () => null,
            );

    try {
      // Snapshot before the attempt, commit to the undo stack only on success —
      // a refused add must not leave a no-op entry for the user to undo.
      final sectionsBefore = List<SelectedSection>.of(tt.selectedSections);
      // The section being switched out has to go first, or the add is refused
      // for the duplicate type it is replacing. Restored below if the add is
      // refused for any other reason, so a rejected switch cannot leave the
      // student with neither section.
      if (replaced != null) {
        timetableService.removeSectionWithoutSaving(
          courseCode,
          replaced.sectionId,
          tt,
        );
      }
      final result = timetableService.addSectionWithoutSaving(
        courseCode,
        sectionId,
        tt,
        allowExamClash: examClashAllowed,
        allowSectionClash: sectionClashAllowed,
      );
      if (!result.isAllowed && replaced != null) {
        tt.selectedSections
          ..clear()
          ..addAll(sectionsBefore);
      }

      if (result.isAllowed) {
        // Stamp the basis onto what was just added. The service builds the
        // SelectedSection and knows nothing about com cods, so this is the one
        // place the choice can be recorded without threading it through it.
        if (basisCode != null) {
          for (var i = 0; i < tt.selectedSections.length; i++) {
            final s = tt.selectedSections[i];
            if (s.courseCode == courseCode && s.comCode == null) {
              tt.selectedSections[i] = s.withComCode(basisCode);
            }
          }
        }
        // One entry for a switch, so undo puts the old section back in a step.
        final what =
            replaced == null
                ? 'Add $courseCode $sectionId'
                : 'Switch $courseCode ${replaced.sectionId} to $sectionId';
        undoRedoService.pushSections(
          sectionsBefore,
          overrideExamClash
              ? '$what (exam clash overridden)'
              : (examClashAllowed || sectionClashAllowed)
              ? '$what (clash bypassed)'
              : what,
        );
        setState(() {
          hasUnsavedChanges = true;
        });
        markUnsaved(true);
        _selectionRevision.value++;
        if (isNewCourse) _warnAboutPrerequisites(courseCode);
        // Warn only when the add actually produced a clash — a bypass that is
        // on but unused shouldn't cry wolf on every add.
        if (examClashAllowed || sectionClashAllowed) {
          final clashes =
              ClashDetector.detectClashes(
                    tt.selectedSections,
                    tt.availableCourses,
                  )
                  .where((w) => w.conflictingCourses.contains(courseCode))
                  .toList();
          if (clashes.isNotEmpty) {
            ToastService.showWarning(
              'Added $courseCode-$sectionId with a clash: ${clashes.first.message}',
            );
          }
        }
      } else if (result.isOverridable) {
        ToastService.showError(
          result.message,
          actionLabel: 'Override',
          onAction:
              () => addSection(courseCode, sectionId, overrideExamClash: true),
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
      timetableService.removeSectionWithoutSaving(courseCode, sectionId, tt);
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
      _pushUndo('Apply timetable repair');
      // Repair plans already contain catalogue-backed, clash-checked selections.
      // Assign them directly so their com codes survive the apply operation.
      tt.selectedSections
        ..clear()
        ..addAll(newSections);
      tt.clashWarnings
        ..clear()
        ..addAll(
          ClashDetector.detectClashes(tt.selectedSections, tt.availableCourses),
        );

      setState(() {
        hasUnsavedChanges = true;
      });
      markUnsaved(true);
      _selectionRevision.value++;
      ToastService.showSuccess('Timetable repair applied');
    } catch (e) {
      showErrorDialog('Error applying timetable repair: $e');
    }
  }

  void quickReplaceCourse(Course selectedCourse, Course replacementCourse) {
    final tt = currentTimetable;
    if (tt == null) return;

    // Same rule as Add: a swap must not be the way a course of the other basis
    // gets onto the grid.
    if (!replacementCourse.offersBasis(creditBasis)) {
      ToastService.showError(
        '${replacementCourse.courseCode} is not offered in ${creditBasis.label} — '
        'this timetable counts in ${creditBasis.label}.',
      );
      return;
    }

    try {
      _pushUndo('Replace ${selectedCourse.courseCode}');
      // Remove all sections of the selected course
      final sectionsToRemove =
          tt.selectedSections
              .where(
                (section) => section.courseCode == selectedCourse.courseCode,
              )
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
      final lectureSection =
          replacementSections.where((s) => s.type == SectionType.L).isNotEmpty
              ? replacementSections.firstWhere((s) => s.type == SectionType.L)
              : null;

      final tutorialSection =
          replacementSections.where((s) => s.type == SectionType.T).isNotEmpty
              ? replacementSections.firstWhere((s) => s.type == SectionType.T)
              : null;

      final practicalSection =
          replacementSections.where((s) => s.type == SectionType.P).isNotEmpty
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
          chosen: result.chosen,
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
      message:
          'Are you sure you want to remove all selected courses from your timetable?',
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
      final outcome = await timetableService.saveTimetable(tt);
      if (!mounted) return;
      final cloudPending =
          outcome == TimetableSaveOutcome.savedLocallyAfterCloudFailure;
      setState(() {
        hasUnsavedChanges = cloudPending;
        isSaving = false;
      });
      markUnsaved(cloudPending);
      if (!cloudPending) triggerSavedIndicator();

      if (cloudPending) {
        ToastService.showWarning(
          'Saved on this device only. Cloud sync failed; retry when online.',
        );
      } else if (outcome == TimetableSaveOutcome.savedLocally) {
        ToastService.showSuccess('Timetable saved on this device');
      } else {
        ToastService.showSuccess('Timetable saved successfully!');
      }
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
    if (returnedShareId != null &&
        returnedShareId != current.shareId &&
        mounted) {
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
      message:
          'Some courses have incomplete selections (missing lab/tutorial/lecture sections). Do you want to continue exporting anyway?',
      confirmLabel: 'Continue',
      icon: Icons.warning_amber_rounded,
    );
  }

  Future<void> exportToICS() async {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) {
      ToastService.showWarning(
        'Add courses to your timetable before exporting.',
      );
      return;
    }

    // Same conditional-export dialog the PNG export uses, so the calendar file
    // carries only the fields the user wants.
    final ExportOptions? exportOptions = await showDialog<ExportOptions>(
      context: context,
      builder:
          (context) => const ExportOptionsDialog(
            showBackgroundOption: false,
            formatLabel: 'ICS',
          ),
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
        actions: [AppButton(label: 'OK', onTap: () => Navigator.pop(context))],
      );
    } catch (e) {
      showErrorDialog('Export failed: $e');
    }
  }

  Future<void> exportToPNG() async {
    final tt = currentTimetable;
    if (tt == null || tt.selectedSections.isEmpty) {
      ToastService.showWarning(
        'Add courses to your timetable before exporting.',
      );
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

      // The capture follows the option, not the app's current brightness, so a
      // user in light mode can still export the dark PNG (the default).
      final themeService = ThemeService();
      final exportTheme =
          exportOptions.darkBackground
              ? themeService.getDarkThemeData(themeService.currentTheme)
              : themeService.getLightThemeData(themeService.currentTheme);

      overlayEntry = OverlayEntry(
        builder:
            (context) => Positioned(
              left: -10000,
              top: -10000,
              child: Theme(
                data: exportTheme,
                child: Material(
                  // Both axes are left unbounded so the grid, and the exam schedule
                  // under it, size to content. A fixed capture width used to be
                  // needed because the old grid's columns were a fixed size; now
                  // that columns divide the available width, pinning it to 2000 px
                  // would stretch a three-day timetable into three 600 px columns.
                  child: UnconstrainedBox(
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
                      selectedSections: tt.selectedSections,
                      availableCourses: tt.availableCourses,
                      size: TimetableSize.extraLarge,
                      isForExport: true,
                      tableKey: tableExportKey,
                      exportOptions: exportOptions,
                    ),
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
        actions: [AppButton(label: 'OK', onTap: () => Navigator.pop(context))],
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
          creditBasis: creditBasis,
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
    final result = await Navigator.push<GeneratorSelection>(
      context,
      FadeSlidePageRoute(page: const GeneratorScreen()),
    );

    // Only "apply to current" returns a selection; "save as new" is handled
    // inside the generator screen and never pops back here.
    if (!mounted || result == null || tt == null) return;
    try {
      _pushUndo('Apply generated timetable');
      // Clear current selections
      tt.selectedSections.clear();

      // Add new selections from generator
      for (final section in result.sections) {
        await timetableService.addSection(
          section.courseCode,
          section.sectionId,
          tt,
        );
      }
      // The run's basis replaces the timetable's, along with everything else
      // that was on it. The service builds selections without com cods, so
      // without this a contact-hours run lands as untagged sections that fall
      // back to their unit variant and get counted against the wrong cap.
      _restateOn(tt, result.creditBasis);
      await timetableService.saveTimetable(tt);

      if (!mounted) return;
      setState(() {});

      ToastService.showSuccess('Generated timetable applied successfully!');
    } catch (e) {
      showErrorDialog('Error applying generated timetable: $e');
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
          currentCampus: CampusService.campusId,
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
    return await AppDialog.confirm(
      context: context,
      title: 'Switch campus?',
      message:
          'Switching campus will clear all courses and sections from this timetable. Are you sure you want to continue?',
      confirmLabel: 'Clear and switch',
      isDangerous: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Shared UI builders
  // ---------------------------------------------------------------------------

  /// Wraps [buildCoursesPanel] with a slim header carrying the collapse
  /// control, shown only in the wide two-pane layout.
  Widget _buildExpandedCoursesPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: TutorialKeys.courseBrowser,
      color: scheme.surface,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Text(
                  'Course browser',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Collapse course browser',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _coursesCollapsed = true),
                ),
              ],
            ),
          ),
          Expanded(child: buildCoursesPanel()),
        ],
      ),
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
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
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

  /// The credit-vs-credit-hours notice for this timetable. Same widget the
  /// generator shows, so the two places the choice is made explain it once.
  Widget _buildCreditBasisNotice() {
    final tt = currentTimetable!;
    return CreditBasisNotice(
      noticeId: tt.id,
      courses: tt.availableCourses,
      toggleHint:
          'Set it with the Credits / Credit hours toggle above the '
          'timetable',
    );
  }

  Widget buildCoursesPanel({VoidCallback? onPanelChanged}) {
    final tt = currentTimetable!;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          _buildCreditBasisNotice(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: SearchFilterWidget(
              key: TutorialKeys.courseSearch,
              onSearchChanged: (query, filters) {
                onSearchChanged(query, filters);
                onPanelChanged?.call();
              },
              hasBranch: hasBranchForPools,
            ),
          ),
          Expanded(
            child: CoursesTabWidget(
              courses: coursesInBasis,
              selectedSections: tt.selectedSections,
              record: _academicRecord,
              projectCount: tt.projectCount,
              allowSectionClash: allowSectionClash,
              creditBasis: creditBasis,
              onRemoveBasis: (basis) async {
                await removeAllInBasis(basis);
                onPanelChanged?.call();
              },
              onProjectCountChanged: (count) {
                setState(() {
                  tt.projectCount = count;
                  hasUnsavedChanges = true;
                });
                markUnsaved(true);
                onPanelChanged?.call();
              },
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  removeSection(courseCode, sectionId);
                } else {
                  addSection(courseCode, sectionId);
                }
                onPanelChanged?.call();
              },
            ),
          ),
          if (ResponsiveService.isDesktop(context)) _buildBuildActionsBar(),
        ],
      ),
    );
  }

  /// The two "build my timetable" actions, docked under the courses panel on
  /// wide layouts.
  ///
  /// They used to be Scaffold FABs, which put them over the bottom-right of the
  /// *grid* — and in fit-to-screen the grid fills its panel exactly, so there
  /// was no scrolling the Friday/Saturday cells out from under them. Docking
  /// here costs the grid nothing. Compact layouts keep these actions in the bottom dock, where they stay
  /// reachable while the timetable remains the primary surface.
  Widget _buildBuildActionsBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: TutorialKeys.addSwapFab,
              onPressed: openAddSwap,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Add / Swap'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                side: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              key: TutorialKeys.generatorFab,
              onPressed: openGenerator,
              icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 18),
              label: const Text('Generate'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                elevation: 0,
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
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          if (tt.clashWarnings.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 8 : 12,
                8,
                isMobile ? 8 : 12,
                0,
              ),
              child: ClashWarningsWidget(warnings: tt.clashWarnings),
            ),
          Expanded(
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
                creditBasis: tt.creditBasis,
                onCreditBasisChanged: setCreditBasis,
                onQuickReplace: quickReplaceCourse,
                onSectionShuffle: sectionShuffle,
                onUndo: isMobile ? undo : null,
                onRedo: isMobile ? redo : null,
                canUndo: isMobile && undoRedoService.canUndo,
                canRedo: isMobile && undoRedoService.canRedo,
                onShowStats: () => _showStatsSheet(context),
                allowExamClash: allowExamClash,
                allowSectionClash: allowSectionClash,
                allowCreditBypass: allowCreditBypass,
                currentCredits: _currentTotalCredits(),
                onBypassChanged: setBypassAllowed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStatsSheet(BuildContext context) {
    final tt = currentTimetable;
    if (tt == null) return;

    Widget statsContent(BuildContext ctx) => TimetableStatsPanel(timetable: tt);

    final isMobile = ResponsiveService.isMobile(context);
    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder:
            (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder:
                  (ctx, scrollController) => Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Timetable Stats',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(child: statsContent(ctx)),
                    ],
                  ),
            ),
      );
    } else {
      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 650,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            'Timetable Stats',
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
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

  Widget buildEditorTitle({required bool standalone}) {
    if (standalone) return AppDesign.appLogo(context, height: 32);

    final scheme = Theme.of(context).colorScheme;
    final compact = !ResponsiveService.isDesktop(context);
    final status =
        authService.isGuest
            ? 'Guest plan'
            : isSaving
            ? 'Saving'
            : hasUnsavedChanges
            ? 'Unsaved'
            : 'Saved';
    final statusColor =
        authService.isGuest
            ? scheme.onSurfaceVariant
            : isSaving || hasUnsavedChanges
            ? scheme.primary
            : AppDesign.success(context);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: currentTimetable!.name),
          if (!compact)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<Widget> buildCommonActions() {
    final isCompactLayout = !ResponsiveService.isDesktop(context);
    return [
      IconButton(
        key: TutorialKeys.commandPalette,
        icon: const Icon(Icons.search_rounded),
        onPressed: _showCommandPalette,
        tooltip: isCompactLayout ? 'Search actions' : 'Search actions  ·  ⌘K',
      ),
      if (!isCompactLayout) ...[
        IconButton(
          onPressed: undoRedoService.canUndo ? undo : null,
          icon: const Icon(Icons.undo_rounded),
          tooltip: undoRedoService.undoDescription ?? 'Undo',
        ),
        IconButton(
          onPressed: undoRedoService.canRedo ? redo : null,
          icon: const Icon(Icons.redo_rounded),
          tooltip: undoRedoService.redoDescription ?? 'Redo',
        ),
      ],
      if (!authService.isGuest && !isCompactLayout)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: FilledButton.icon(
            key: const ValueKey('editor-save'),
            onPressed: hasUnsavedChanges && !isSaving ? saveTimetable : null,
            icon:
                isSaving
                    ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Icon(
                      hasUnsavedChanges ? Icons.save_outlined : Icons.check,
                      size: 17,
                    ),
            label: Text(
              isSaving
                  ? 'Saving'
                  : hasUnsavedChanges
                  ? 'Save'
                  : 'Saved',
            ),
            style: FilledButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
      if (!isCompactLayout) ...[
        CampusSelectorWidget(
          key: TutorialKeys.campusSelector,
          confirmSwitch: () => confirmCampusSwitch(),
          onCampusChanged: onCampusChanged,
        ),
        IconButton(
          key: TutorialKeys.shareButton,
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: shareTimetable,
          tooltip: 'Share timetable',
        ),
      ],
      PopupMenuButton<String>(
        key: TutorialKeys.toolsMenu,
        icon: const Icon(Icons.more_horiz_rounded),
        tooltip: 'Editor menu',
        onSelected: (value) {
          final tool = AppTools.byName(value);
          if (tool != null) {
            openTool(tool);
            return;
          }
          switch (value) {
            case 'share':
              shareTimetable();
              break;
            case 'page_info':
              PageInfoHelper.show(context, PageInfoHelper.timetableCreator);
              break;
            case 'appearance':
              ThemeSelectorDialog.show(context);
              break;
            case 'import_tt':
              importFromTT();
              break;
            case 'export_tt':
              exportToTTWithFilePicker();
              break;
            case 'export_ics':
              exportToICS();
              break;
            case 'export_png':
              exportToPNG();
              break;
            case 'logout':
              logout();
              break;
            case 'github':
              openGitHub();
              break;
          }
        },
        itemBuilder:
            (context) => [
              if (isCompactLayout) ...[
                CampusSelectorWidget.menuEntry<String>(
                  context,
                  confirmSwitch: () => confirmCampusSwitch(),
                  onCampusChanged: onCampusChanged,
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('Share timetable'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'page_info',
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('About this editor'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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
              const PopupMenuItem(
                value: 'import_tt',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Import .tt file'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_tt',
                child: ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('Export .tt file'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_ics',
                child: ListTile(
                  leading: Icon(Icons.calendar_today_outlined),
                  title: Text('Export calendar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_png',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Export image'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Appearance'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (authService.isAuthenticated)
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout_rounded),
                    title: Text('Sign out'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'github',
                child: ListTile(
                  leading: Icon(Icons.star_border_rounded),
                  title: Text('Star on GitHub'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget buildBodyLayout(bool isWideScreen) {
    final scheme = Theme.of(context).colorScheme;
    if (isWideScreen) {
      return ColoredBox(
        color: scheme.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final preferred = constraints.maxWidth * 0.29;
            final expandedWidth = preferred.clamp(340.0, 410.0);
            const railWidth = 56.0;
            final collapsed = _coursesCollapsed;
            final duration =
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 260);
            const curve = Curves.easeOutCubic;
            return Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  width: collapsed ? railWidth : expandedWidth,
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
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outline.withValues(alpha: 0.14),
                ),
                Expanded(child: buildTimetablePanel()),
              ],
            );
          },
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: buildTimetablePanel()),
        _buildMobileEditorDock(),
      ],
    );
  }

  Widget _buildMobileEditorDock() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 62,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: TutorialKeys.courseBrowser,
                  onPressed: _showMobileCourses,
                  icon: const Icon(Icons.library_books_outlined, size: 19),
                  label: const Text('Courses'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: TutorialKeys.generatorFab,
                  onPressed: () => _showMobileBuildActions(context),
                  icon: const Icon(
                    Icons.auto_awesome_mosaic_outlined,
                    size: 19,
                  ),
                  label: const Text('Build'),
                  style: FilledButton.styleFrom(elevation: 0),
                ),
              ),
              if (!authService.isGuest) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  key: const ValueKey('mobile-editor-save'),
                  onPressed:
                      hasUnsavedChanges && !isSaving ? saveTimetable : null,
                  icon:
                      isSaving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(
                            hasUnsavedChanges
                                ? Icons.save_outlined
                                : Icons.check_rounded,
                          ),
                  tooltip: hasUnsavedChanges ? 'Save timetable' : 'Saved',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileCourses() async {
    final scheme = Theme.of(context).colorScheme;
    // The sheet is a separate route, so editor setState calls do not rebuild it.
    final revision = ValueNotifier<int>(0);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: scheme.surface,
        builder:
            (sheetContext) => ValueListenableBuilder<int>(
              valueListenable: revision,
              builder:
                  (context, _, __) => DraggableScrollableSheet(
                    initialChildSize: 0.94,
                    minChildSize: 0.65,
                    maxChildSize: 0.98,
                    expand: false,
                    builder:
                        (context, scrollController) => Column(
                          children: [
                            Container(
                              height: 52,
                              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.outline.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Course browser',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed:
                                        () => Navigator.pop(sheetContext),
                                    icon: const Icon(Icons.close_rounded),
                                    tooltip: 'Close course browser',
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: buildCoursesPanel(
                                onPanelChanged: () => revision.value++,
                              ),
                            ),
                          ],
                        ),
                  ),
            ),
      );
    } finally {
      revision.dispose();
      // A reopened sheet has a fresh, blank search field; its results must match.
      final tt = currentTimetable;
      if (mounted && tt != null) {
        setState(() => filteredCourses = tt.availableCourses);
      }
    }
  }

  Widget? buildFABs(bool isWideScreen) => null;

  /// Compact-layout chooser for automatic generation or manual section work.
  void _showMobileBuildActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
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
                  leading: Icon(
                    Icons.auto_awesome_mosaic,
                    color: scheme.primary,
                  ),
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
      final importedTimetable =
          await ExportService.importFromTTWithFilePicker();
      if (importedTimetable == null || !mounted) return;

      final shouldReplace = await AppDialog.confirm(
        context: context,
        title: 'Import Timetable',
        message:
            'Are you sure you want to import "${importedTimetable.name}"?\n\n'
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

        final updatedImportedTimetable = importedTimetable.copyWith(
          availableCourses: reloadedTimetable.availableCourses,
          clashWarnings: clashWarnings,
          // Imported files must not inherit control of another timetable's share.
          shareId: () => null,
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
      ToastService.showWarning(
        'Add courses to your timetable before exporting.',
      );
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
          AppButton(label: 'OK', onTap: () => Navigator.of(context).pop()),
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
