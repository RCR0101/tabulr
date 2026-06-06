import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
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
  static final courseSearch = GlobalKey(debugLabel: 'tutorial_search');
  static final timetableGrid = GlobalKey(debugLabel: 'tutorial_grid');
  static final generatorFab = GlobalKey(debugLabel: 'tutorial_generator');
  static final addSwapFab = GlobalKey(debugLabel: 'tutorial_add_swap');

  // CGPA Calculator
  static final cgpaSummary = GlobalKey(debugLabel: 'tutorial_cgpa_summary');
  static final semesterTabs = GlobalKey(debugLabel: 'tutorial_semester_tabs');
  static final cgpaActions = GlobalKey(debugLabel: 'tutorial_cgpa_actions');

  // Acad Drives
  static final acadDrivesYourCourses = GlobalKey(debugLabel: 'tutorial_your_courses');
  static final acadDrivesSubmit = GlobalKey(debugLabel: 'tutorial_submit_drive');
  static final acadDrivesSearch = GlobalKey(debugLabel: 'tutorial_acad_search');

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

  bool _shouldShow(String section) {
    final auth = AuthService();
    if (!auth.isAuthenticated) return false;
    return !UserSettingsService().isTutorialCompleted(section);
  }

  static const _sectionTimetableList = 'timetable_list';
  static const _sectionEditor = 'editor';
  static const _sectionCGPA = 'cgpa';
  static const _sectionAcadDrives = 'acad_drives';

  void showTimetableListTutorial(BuildContext context) {
    if (_isShowing || !_shouldShow(_sectionTimetableList)) return;
    _isShowing = true;
    _currentSection = _sectionTimetableList;

    final targets = <TargetFocus>[];

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

  void showEditorTutorial(BuildContext context) {
    if (_isShowing || !_shouldShow(_sectionEditor)) return;
    _isShowing = true;
    _currentSection = _sectionEditor;

    final targets = <TargetFocus>[];

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
      key: TutorialKeys.timetableGrid,
      title: 'Your Timetable',
      description: 'Your weekly schedule builds here as you add sections. Clashes are detected automatically.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addTarget(
      targets,
      key: TutorialKeys.generatorFab,
      title: 'Auto-Generate',
      description: 'Pick your courses and let the generator find the best clash-free timetable for you.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
    );

    _addTarget(
      targets,
      key: TutorialKeys.addSwapFab,
      title: 'Add & Swap',
      description: 'Add a new course or swap sections without rebuilding your entire timetable.',
      shape: ShapeLightFocus.RRect,
      align: ContentAlign.top,
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

  void showCGPATutorial(BuildContext context) {
    if (_isShowing || !_shouldShow(_sectionCGPA)) return;
    _isShowing = true;
    _currentSection = _sectionCGPA;

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

  void showAcadDrivesTutorial(BuildContext context) {
    if (_isShowing || !_shouldShow(_sectionAcadDrives)) return;
    _isShowing = true;
    _currentSection = _sectionAcadDrives;

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
        _completeTutorial();
        return true;
      },
      onFinish: _completeTutorial,
    )..show(context: context);
  }

  void _completeTutorial() {
    _isShowing = false;
    _currentTutorial = null;
    if (_currentSection != null) {
      UserSettingsService().markTutorialCompleted(_currentSection!);
      _currentSection = null;
    }
  }

  void dismiss() {
    _currentTutorial?.skip();
    _currentTutorial = null;
    _isShowing = false;
  }

  void _addTarget(
    List<TargetFocus> targets, {
    required GlobalKey key,
    required String title,
    required String description,
    ShapeLightFocus shape = ShapeLightFocus.RRect,
    ContentAlign align = ContentAlign.bottom,
    CustomTargetContentPosition? customPosition,
  }) {
    if (key.currentContext == null) return;

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
