import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../constants/app_constants.dart';
import '../../widgets/app_drawer.dart';
import '../data/user_settings_service.dart';
import '../data/auth_service.dart';

class TutorialKeys {
  TutorialKeys._();

  // TimetablesScreen
  static final sidebarNav = GlobalKey(debugLabel: 'tutorial_sidebar');
  static final newTimetableBtn = GlobalKey(debugLabel: 'tutorial_new_tt');
  static final importCodeBtn = GlobalKey(debugLabel: 'tutorial_import_code');
  static final compareBtn = GlobalKey(debugLabel: 'tutorial_compare');
  static final timetableCard = GlobalKey(debugLabel: 'tutorial_tt_card');

  // Timetable Editor (HomeScreen)
  static final commandPalette = GlobalKey(debugLabel: 'tutorial_command_palette');
  static final courseSearch = GlobalKey(debugLabel: 'tutorial_search');
  static final timetableGrid = GlobalKey(debugLabel: 'tutorial_grid');
  static final generatorFab = GlobalKey(debugLabel: 'tutorial_generator');
  static final addSwapFab = GlobalKey(debugLabel: 'tutorial_add_swap');
  static final campusSelector = GlobalKey(debugLabel: 'tutorial_campus');
  static final shareButton = GlobalKey(debugLabel: 'tutorial_share');
  static final toolsMenu = GlobalKey(debugLabel: 'tutorial_tools');

  // CGPA Calculator
  static final cgpaSummary = GlobalKey(debugLabel: 'tutorial_cgpa_summary');
  static final semesterTabs = GlobalKey(debugLabel: 'tutorial_semester_tabs');
  static final cgpaActions = GlobalKey(debugLabel: 'tutorial_cgpa_actions');

  // Acad Drives
  static final acadDrivesYourCourses = GlobalKey(debugLabel: 'tutorial_your_courses');
  static final acadDrivesSubmit = GlobalKey(debugLabel: 'tutorial_submit_drive');
  static final acadDrivesSearch = GlobalKey(debugLabel: 'tutorial_acad_search');

  // Admin
  static final adminManagement = GlobalKey(debugLabel: 'tutorial_admin_mgmt');
  static final adminTimetableUpload = GlobalKey(debugLabel: 'tutorial_admin_tt_upload');
  static final adminExamUpload = GlobalKey(debugLabel: 'tutorial_admin_exam_upload');

  // Page info buttons (per screen)
  static final infoTimetableList = GlobalKey(debugLabel: 'tutorial_info_tt_list');
  static final infoCalendar = GlobalKey(debugLabel: 'tutorial_info_calendar');
  static final infoFreeSlot = GlobalKey(debugLabel: 'tutorial_info_free_slot');
  static final infoCGPA = GlobalKey(debugLabel: 'tutorial_info_cgpa');
  static final infoExamSeating = GlobalKey(debugLabel: 'tutorial_info_exam');
  static final infoAcadDrives = GlobalKey(debugLabel: 'tutorial_info_acad');
  static final infoProfChambers = GlobalKey(debugLabel: 'tutorial_info_prof');
  static final infoAnnouncements = GlobalKey(debugLabel: 'tutorial_info_announce');
}

enum TutorialSection {
  timetableList('Timetable List'),
  timetableEditor('Timetable Editor');

  final String label;
  const TutorialSection(this.label);
}

class TutorialService {
  TutorialService._();
  static final TutorialService _instance = TutorialService._();
  factory TutorialService() => _instance;

  bool _isShowing = false;
  TutorialCoachMark? _currentTutorial;
  String? _currentSection;

  /// Spotlights are one-shot: dismissing (skip) marks them seen just like
  /// finishing, whereas skipping a full tour only defers it (see [_skipTutorial]).
  bool _currentIsSpotlight = false;

  /// Sections dismissed via Skip in this app session. Combined with the
  /// persisted `{section}_skipped` marker, this stops a skipped tour from
  /// re-popping immediately while still allowing an explicit replay.
  final Set<String> _dismissedThisSession = {};

  static String _skippedFlag(String section) => '${section}_skipped';

  /// Set once the user skips *any* tour — suppresses all further auto-tours and
  /// spotlights so a new user isn't nagged screen after screen. Explicit replay
  /// (force: true, e.g. "Show me around") bypasses it.
  static const String _globalSkipFlag = 'onboarding_skipped';

  bool get _onboardingSkipped =>
      UserSettingsService().isTutorialCompleted(_globalSkipFlag);

  bool _shouldShow(String section) {
    final auth = AuthService();
    if (!auth.isAuthenticated) return false;
    if (_onboardingSkipped) return false;
    if (_dismissedThisSession.contains(section)) return false;
    final settings = UserSettingsService();
    return !settings.isTutorialCompleted(section) &&
        !settings.isTutorialCompleted(_skippedFlag(section));
  }

  static const _sectionTimetableList = TutorialSections.timetableList;
  static const _sectionEditor = TutorialSections.editor;
  static const _sectionCGPA = TutorialSections.cgpa;
  static const _sectionAcadDrives = TutorialSections.acadDrives;
  static const _sectionAdmin = TutorialSections.admin;

  void showTimetableListTutorial(BuildContext context, {bool force = false}) {
    if (_isShowing) return;
    if (!force && !_shouldShow(_sectionTimetableList)) return;
    _isShowing = true;
    _currentSection = _sectionTimetableList;
    _currentIsSpotlight = false;

    final targets = <TargetFocus>[];

    _addTarget(
      targets,
      key: TutorialKeys.sidebarNav,
      title: 'Everything lives here',
      description: 'Your other tools — Free Slot Finder, CGPA, Acad Drives, Prof Chambers, Bug Report and more — are one tap away in this menu.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.right,
    );

    _addTarget(
      targets,
      key: TutorialKeys.newTimetableBtn,
      title: 'Create a Timetable',
      description: 'Tap here to create a new timetable. You can have multiple timetables to compare different course combinations.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addTarget(
      targets,
      key: TutorialKeys.importCodeBtn,
      title: 'Import from Friends',
      description: 'Got a share code from a friend? Import their timetable instantly.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addTarget(
      targets,
      key: TutorialKeys.compareBtn,
      title: 'Compare Timetables',
      description: 'View two timetables side by side to decide which one works best.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addInfoButtonTarget(targets, TutorialKeys.infoTimetableList);

    if (targets.isEmpty) {
      _isShowing = false;
      return;
    }

    _showTutorial(context, targets);
  }

  void showEditorTutorial(BuildContext context, {bool force = false}) {
    if (_isShowing) return;
    if (!force && !_shouldShow(_sectionEditor)) return;
    _isShowing = true;
    _currentSection = _sectionEditor;
    _currentIsSpotlight = false;

    final targets = <TargetFocus>[];

    _addTarget(
      targets,
      key: TutorialKeys.commandPalette,
      title: 'Search anything (⌘K)',
      description: 'Press this — or ⌘K / Ctrl+K — to jump to any feature, action, theme or saved timetable from one search box. The fastest way around Tabulr.',
      shape: ShapeLightFocus.Circle,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.campusSelector,
      title: 'Select Campus',
      description: 'Choose your campus — Pilani, Goa, or Hyderabad. This loads the correct course catalog and time slots.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.courseSearch,
      title: 'Search Courses',
      description: 'Search by course code, name, or instructor. Tap a section to add it to your timetable.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.generatorFab,
      title: 'Auto-Generate',
      description: 'Pick your courses and let the generator find the best clash-free timetable for you — or add & swap sections from here too.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addTarget(
      targets,
      key: TutorialKeys.toolsMenu,
      title: 'Tools & more',
      description: 'Course guide, prerequisites, discipline & humanities electives, share, and import/export all live here.',
      shape: ShapeLightFocus.Circle,
      align: ContentAlign.bottom,
    );

    if (targets.isEmpty) {
      _isShowing = false;
      return;
    }

    _showTutorial(context, targets);
  }

  void _addInfoButtonTarget(List<TargetFocus> targets, GlobalKey key) {
    _addTarget(
      targets,
      key: key,
      title: 'Page Guide',
      description: 'Tap this anytime to see what you can do on this page — features, shortcuts, and tips.',
      shape: ShapeLightFocus.Circle,
      align: ContentAlign.bottom,
    );
  }

  void showCGPATutorial(BuildContext context, {bool force = false}) {
    if (_isShowing) return;
    if (!force && !_shouldShow(_sectionCGPA)) return;
    _isShowing = true;
    _currentSection = _sectionCGPA;
    _currentIsSpotlight = false;

    final targets = <TargetFocus>[];

    _addTarget(
      targets,
      key: TutorialKeys.cgpaSummary,
      title: 'Your CGPA',
      description: 'Your overall CGPA and total credits at a glance. Tap to see a semester-by-semester breakdown.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.semesterTabs,
      title: 'Semester Tabs',
      description: 'Switch between semesters to add courses and grades. Long-press a tab to remove it, or tap + to add a new one.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.cgpaActions,
      title: 'Quick Actions',
      description: 'Import grades from your performance sheet PDF, load CDCs automatically, or plan future grades with Grade Planner and CG Booster.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addInfoButtonTarget(targets, TutorialKeys.infoCGPA);

    if (targets.isEmpty) {
      _isShowing = false;
      return;
    }

    _showTutorial(context, targets);
  }

  void showAcadDrivesTutorial(BuildContext context, {bool force = false}) {
    if (_isShowing) return;
    if (!force && !_shouldShow(_sectionAcadDrives)) return;
    _isShowing = true;
    _currentSection = _sectionAcadDrives;
    _currentIsSpotlight = false;

    final targets = <TargetFocus>[];

    _addTarget(
      targets,
      key: TutorialKeys.acadDrivesYourCourses,
      title: 'Your Courses',
      description: 'Courses from your timetable appear here first for quick access to their study materials.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.acadDrivesSearch,
      title: 'Search Resources',
      description: 'Search across all courses to find notes, slides, past papers, and assignments.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.acadDrivesSubmit,
      title: 'Contribute',
      description: 'Have study materials? Submit a Google Drive link to share resources with everyone.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addInfoButtonTarget(targets, TutorialKeys.infoAcadDrives);

    if (targets.isEmpty) {
      _isShowing = false;
      return;
    }

    _showTutorial(context, targets);
  }

  void showAdminTutorial(BuildContext context, {bool force = false}) {
    if (_isShowing) return;
    if (!force && !_shouldShow(_sectionAdmin)) return;
    _isShowing = true;
    _currentSection = _sectionAdmin;
    _currentIsSpotlight = false;

    final targets = <TargetFocus>[];

    _addTarget(
      targets,
      key: TutorialKeys.adminManagement,
      title: 'Data Management',
      description: 'Edit courses, exam seating, professor chambers, and CDC structure. Changes go live immediately.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.bottom,
    );

    _addTarget(
      targets,
      key: TutorialKeys.adminTimetableUpload,
      title: 'Timetable Upload',
      description: 'Upload timetable PDFs per campus. Set page ranges and header exclusions, then parse and push to Firestore.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
      maxContentWidth: 320,
    );

    _addTarget(
      targets,
      key: TutorialKeys.adminExamUpload,
      title: 'Exam Seating Upload',
      description: 'Upload exam seating PDFs to parse room and seat assignments for students.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
      maxContentWidth: 320,
    );

    if (targets.isEmpty) {
      _isShowing = false;
      return;
    }

    _showTutorial(context, targets);
  }

  /// Auto-starts a shell screen's tour as soon as it's eligible and its target
  /// widgets are laid out. See [_autoStart] for why a fixed delay isn't enough.
  void autoStart(
    BuildContext context,
    DrawerScreen screen, {
    required bool Function() isMounted,
  }) {
    final section = _sectionForScreen(screen);
    if (section == null) return;
    _autoStart(
      context,
      section: section,
      isMounted: isMounted,
      start: (ctx) => _showForScreen(ctx, screen),
      spotlight: _spotlightForScreen(screen),
    );
  }

  /// Auto-starts the timetable editor tour (the editor isn't a shell screen, so
  /// it has its own entry point). Falls back to the Tools spotlight for users
  /// who previously skipped the full editor tour.
  void autoStartEditor(BuildContext context, {required bool Function() isMounted}) {
    _autoStart(
      context,
      section: _sectionEditor,
      isMounted: isMounted,
      start: showEditorTutorial,
      spotlight: showToolsSpotlight,
    );
  }

  /// Cold start races two things we can't predict — auth restoring and the
  /// first layout pass — so a fixed delay either fires too early (auth not ready
  /// → tour silently skipped) or misses entirely. This retries on a short
  /// cadence until the tour shows, the section is permanently done, the widget
  /// unmounts, or the window elapses. When the tour is already done (e.g. the
  /// user skipped it in a past session), [spotlight] gets a chance instead.
  void _autoStart(
    BuildContext context, {
    required String section,
    required bool Function() isMounted,
    required void Function(BuildContext) start,
    void Function(BuildContext)? spotlight,
  }) {
    void attempt(int remaining) {
      if (!isMounted()) return;
      if (_isShowing) return; // something (maybe this) is already up
      if (_permanentlyDone(section)) {
        // Tour won't run — offer the skipper spotlight instead (it self-guards
        // so finishers and same-session skippers still see nothing).
        spotlight?.call(context);
        return;
      }
      start(context);
      if (_isShowing || remaining <= 1) return; // started, or gave up
      // Not shown yet — auth still restoring or targets not laid out. Retry.
      Future.delayed(const Duration(milliseconds: 200), () => attempt(remaining - 1));
    }

    // ~5s window: enough to outlast a slow auth restore without nagging forever.
    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(25));
  }

  /// True once the tour has been finished, skipped, or dismissed this session —
  /// i.e. there's permanently nothing to auto-show. Distinct from a transient
  /// "auth not ready yet", which [_autoStart] must keep retrying through.
  bool _permanentlyDone(String section) {
    if (_onboardingSkipped) return true;
    if (_dismissedThisSession.contains(section)) return true;
    final settings = UserSettingsService();
    return settings.isTutorialCompleted(section) ||
        settings.isTutorialCompleted(_skippedFlag(section));
  }

  String? _sectionForScreen(DrawerScreen screen) => switch (screen) {
        DrawerScreen.timetables => _sectionTimetableList,
        DrawerScreen.cgpaCalculator => _sectionCGPA,
        DrawerScreen.acadDrives => _sectionAcadDrives,
        DrawerScreen.admin => _sectionAdmin,
        _ => null,
      };

  void Function(BuildContext)? _spotlightForScreen(DrawerScreen screen) =>
      switch (screen) {
        DrawerScreen.cgpaCalculator => showCgpaToolsSpotlight,
        _ => null,
      };

  void _showForScreen(BuildContext context, DrawerScreen screen) {
    switch (screen) {
      case DrawerScreen.timetables:
        showTimetableListTutorial(context);
        break;
      case DrawerScreen.cgpaCalculator:
        showCGPATutorial(context);
        break;
      case DrawerScreen.acadDrives:
        showAcadDrivesTutorial(context);
        break;
      case DrawerScreen.admin:
        showAdminTutorial(context);
        break;
      default:
        break;
    }
  }

  /// Replays the tour for the given [screen] regardless of prior state.
  /// Returns false if the screen has no guided tour.
  bool replayForScreen(BuildContext context, DrawerScreen screen) {
    switch (screen) {
      case DrawerScreen.timetables:
        showTimetableListTutorial(context, force: true);
        return true;
      case DrawerScreen.cgpaCalculator:
        showCGPATutorial(context, force: true);
        return true;
      case DrawerScreen.acadDrives:
        showAcadDrivesTutorial(context, force: true);
        return true;
      case DrawerScreen.admin:
        showAdminTutorial(context, force: true);
        return true;
      default:
        return false;
    }
  }

  /// One-time spotlight on the editor Tools menu, shown to users who skipped
  /// the full editor tour so its nested tools (Course Guide, Prerequisites,
  /// electives, import/export) aren't lost.
  void showToolsSpotlight(BuildContext context) {
    _maybeShowSpotlight(
      context,
      flag: 'spotlight_tools',
      afterSection: _sectionEditor,
      key: TutorialKeys.toolsMenu,
      title: 'More tools in here',
      description:
          'Course Guide, Prerequisites, Discipline & Humanities electives, and import/export all live in this menu.',
      shape: ShapeLightFocus.Circle,
    );
  }

  /// One-time spotlight on the CGPA quick actions (Grade Planner, CG Booster,
  /// imports) for users who skipped the CGPA tour.
  void showCgpaToolsSpotlight(BuildContext context) {
    _maybeShowSpotlight(
      context,
      flag: 'spotlight_cgpa_tools',
      afterSection: _sectionCGPA,
      key: TutorialKeys.cgpaActions,
      title: 'Plan ahead from here',
      description:
          'Grade Planner, CG Booster, performance-sheet import and auto-load CDCs are all tucked into these quick actions.',
      shape: ShapeLightFocus.RRect,
    );
  }

  void _maybeShowSpotlight(
    BuildContext context, {
    required String flag,
    required String afterSection,
    required GlobalKey key,
    required String title,
    required String description,
    required ShapeLightFocus shape,
  }) {
    if (_isShowing) return;
    if (!AuthService().isAuthenticated) return;
    if (_onboardingSkipped) return; // user opted out of onboarding entirely
    final settings = UserSettingsService();
    if (settings.isTutorialCompleted(flag)) return; // already seen
    // Only surface to users who skipped the full tour (finishers already saw
    // it); and never in the same session as the skip.
    if (settings.isTutorialCompleted(afterSection)) return;
    if (!settings.isTutorialCompleted(_skippedFlag(afterSection))) return;
    if (_dismissedThisSession.contains(afterSection)) return;

    final targets = <TargetFocus>[];
    _addTarget(targets,
        key: key,
        title: title,
        description: description,
        shape: shape,
        align: ContentAlign.bottom);
    if (targets.isEmpty) return;

    _isShowing = true;
    _currentSection = flag;
    _currentIsSpotlight = true;
    _showTutorial(context, targets);
  }

  void _showTutorial(BuildContext context, List<TargetFocus> targets) {
    _currentTutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      hideSkip: true,
      paddingFocus: 8,
      focusAnimationDuration: const Duration(milliseconds: 400),
      unFocusAnimationDuration: const Duration(milliseconds: 200),
      pulseEnable: false,
      onSkip: () {
        _skipTutorial();
        return true;
      },
      onFinish: _completeTutorial,
    )..show(context: context);
  }

  void _completeTutorial() {
    _isShowing = false;
    _currentTutorial = null;
    _currentIsSpotlight = false;
    if (_currentSection != null) {
      UserSettingsService().markTutorialCompleted(_currentSection!);
      _currentSection = null;
    }
  }

  /// Skipping a full tour opts the user out of onboarding globally — the
  /// `_globalSkipFlag` stops every other tour/spotlight from auto-firing so they
  /// aren't nagged screen after screen. Individual tours stay replayable via
  /// force (e.g. "Show me around"). Skipping a spotlight just marks it seen.
  void _skipTutorial() {
    _isShowing = false;
    _currentTutorial = null;
    final section = _currentSection;
    final wasSpotlight = _currentIsSpotlight;
    _currentSection = null;
    _currentIsSpotlight = false;
    if (section == null) return;
    if (wasSpotlight) {
      UserSettingsService().markTutorialCompleted(section);
    } else {
      _dismissedThisSession.add(section);
      UserSettingsService().markTutorialCompleted(_skippedFlag(section));
      // One skip = done with onboarding everywhere.
      UserSettingsService().markTutorialCompleted(_globalSkipFlag);
    }
  }

  void dismiss() {
    _currentTutorial?.skip();
    _currentTutorial = null;
    _isShowing = false;
  }

  /// Whether [key]'s widget is currently laid out and on-screen. Guards the
  /// tour against targets that exist in the tree but aren't visible — offstage
  /// tab pages (translated off to the side), closed drawers/menus, or anything
  /// scrolled fully out of view.
  bool _isTargetOnScreen(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return false;
    final render = context.findRenderObject();
    // `attached` must hold before localToGlobal (it walks the ancestor chain).
    if (render is! RenderBox || !render.attached || !render.hasSize) return false;
    final size = render.size;
    if (size.shortestSide <= 0) return false;
    final screenSize = MediaQuery.maybeOf(context)?.size;
    if (screenSize == null) return false;
    final topLeft = render.localToGlobal(Offset.zero);
    // Require a real overlap with the screen — an offstage page sits at a large
    // negative/positive x and won't intersect.
    return (topLeft & size).overlaps(Offset.zero & screenSize);
  }

  void _addTarget(
    List<TargetFocus> targets, {
    required GlobalKey key,
    required String title,
    required String description,
    ShapeLightFocus shape = ShapeLightFocus.RRect,
    ContentAlign align = ContentAlign.bottom,
    CustomTargetContentPosition? customPosition,
    double? maxContentWidth,
  }) {
    // Skip anything that isn't actually visible on the current screen — a null
    // context, or a widget that's built but off-screen (a closed drawer, an
    // inactive tab, a collapsed menu). Spotlighting those produces a dark
    // screen with the highlight in empty space and no way forward on mobile.
    if (!_isTargetOnScreen(key)) return;

    targets.add(
      TargetFocus(
        identify: key.toString(),
        keyTarget: key,
        shape: shape,
        radius: 12,
        contents: [
          TargetContent(
            align: align,
            customPosition: customPosition,
            builder: (context, controller) {
              final scheme = Theme.of(context).colorScheme;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Container(
                  constraints: maxContentWidth != null
                      ? BoxConstraints(maxWidth: maxContentWidth)
                      : null,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _currentTutorial?.skip(),
                            child: Text(
                              'Skip',
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => controller.previous(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'Back',
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => controller.next(),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                            ),
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
