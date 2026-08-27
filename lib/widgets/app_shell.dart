import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data/auth_service.dart';
import '../services/data/cgpa_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/tutorial_service.dart';
import '../screens/timetables_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/cgpa_calculator_screen.dart';
import '../screens/exam_seating_screen.dart';
import '../screens/acad_drives_screen.dart';
import '../screens/professors_screen.dart';
import '../screens/course_announcements_screen.dart';
import '../screens/bug_report_screen.dart';
import '../screens/faq_screen.dart';
import '../screens/minors_screen.dart';
import '../screens/guide_screen.dart';
// Deferred: ~7k lines across screens/admin/ that only allowlisted accounts can
// open, otherwise compiled into the bundle every visitor downloads.
import '../screens/admin_screen.dart' deferred as admin_screen;
import '../screens/free_slot_finder_screen.dart';
import '../services/data/admin_service.dart';
import '../utils/app_routes.dart';
import 'common/deferred_screen.dart';
import 'app_destinations.dart';
import 'app_tools.dart';
import 'app_workspaces.dart';
import 'workspace_frame.dart';
import 'command_palette.dart';
import 'theme_selector_widget.dart';

class AppShell extends StatefulWidget {
  final DrawerScreen initialScreen;

  const AppShell({super.key, this.initialScreen = AppRoutes.defaultScreen});

  /// The mounted shell, if there is one.
  ///
  /// Routes pushed on top of the shell (the timetable editor) can't reach it
  /// through the widget tree — a pushed route is the Navigator's sibling of the
  /// shell, not its descendant — so [goTo] goes through here instead.
  static _AppShellState? _active;

  /// Switches the screen the shell is showing. Does nothing when no shell is
  /// mounted, which is the case in widget tests and on the auth route.
  ///
  /// This only changes what sits *underneath* the current route; callers on a
  /// pushed route are responsible for leaving it themselves.
  ///
  /// Safe to call when the browser is the one that moved: the URL the Router
  /// then writes is the one it just read, so it replaces rather than stacks.
  static void goTo(DrawerScreen screen) => _active?._onScreenSelected(screen);

  /// The tab the mounted shell is showing, or null when none is mounted.
  static DrawerScreen? get currentScreen => _active?._currentScreen;

  static AppTool? get currentTool => _active?._currentTool;
  static String? get guideAnchor => _active?._guideAnchor;
  static bool get isMounted => _active != null;

  /// Only intercept at the shell root. A contextual editor tool must keep its
  /// selection link and its normal route/unsaved-changes behaviour.
  static bool openTool(AppTool tool, {String? guideAnchor}) {
    final active = _active;
    if (active == null ||
        AppWorkspaces.forTool(tool) == null ||
        !AppTools.of(tool).isReachable) {
      return false;
    }
    active._onToolSelected(tool, guideAnchor: guideAnchor);
    return true;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late DrawerScreen _currentScreen;
  AppTool? _currentTool;
  String? _guideAnchor;
  final Set<AppTool> _visitedTools = {};
  final Map<AppWorkspace, WorkspaceEntry> _lastEntries = {};
  final AdminService _adminService = AdminService();
  bool _sidebarCollapsed = false;
  final Set<DrawerScreen> _visitedScreens = {};

  static const _allScreens = DrawerScreen.values;

  @override
  void initState() {
    super.initState();
    // A deep link picks the opening tab. [Uri.base] rather than a value
    // captured at startup: it tracks the live URL on web, so a shell rebuilt
    // later — a sign-out and back in — reopens wherever the user actually is.
    _currentScreen = AppRoutes.screenIn(Uri.base) ?? widget.initialScreen;
    _visitedScreens.add(_currentScreen);
    final launchTool = AppRoutes.pageIn(Uri.base)?.tool;
    if (launchTool != null &&
        AppWorkspaces.forTool(launchTool) != null &&
        AppRoutes.history.topRouteName != AppRoutes.pagePathIn(Uri.base)) {
      _currentTool = launchTool;
      if (launchTool == AppTool.guide && Uri.base.fragment.isNotEmpty) {
        _guideAnchor = Uri.base.fragment;
      }
      _visitedTools.add(launchTool);
    }
    final initialEntry = _workspace.entries.firstWhere(
      (entry) => _currentTool == null
          ? entry.screen == _currentScreen
          : entry.tool == _currentTool,
    );
    _lastEntries[_workspace.workspace] = initialEntry;
    _adminService.addListener(_onAccessChanged);
    AppShell._active = this;
    // The address bar may name a tab this user cannot open, or nothing at all;
    // either way it should now say what this shell actually opened.
    AppRoutes.refresh();
    _openLaunchUrlPage();
    // Handle Cmd/Ctrl+K at the keyboard level so it works regardless of where
    // focus currently sits — a focused CallbackShortcuts stops firing once focus
    // drifts off its subtree (tab switches, closed dialogs).
    HardwareKeyboard.instance.addHandler(_handleGlobalCommandPaletteKey);
    if (AuthService().isAuthenticated) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && isSignedIn()) CGPAService().prefetch();
      });
      // Load saved defaults so consumers (exam seating, CDC loader, …) can
      // read them synchronously.
      ProfileService().load();
    }
  }

  /// Opens the pushed screen the launch URL names, if it is not already open.
  ///
  /// [AppRouterDelegate.setInitialRoutePath] already tried, after the first
  /// frame, so a *public* screen like `/credits` is stacked over this shell by
  /// the time we get here — pushing it again put two copies on the stack and
  /// made the user close it twice. Hence the check rather than an unconditional
  /// push.
  ///
  /// The rest need this. Their routes are gated on being signed in, and that
  /// first attempt runs before Firebase Auth has restored the persisted web
  /// session, so `currentUser` is still null and the route is refused.
  /// Cold-loading `/prerequisites` landed on the default tab even for a
  /// signed-in user. This shell only exists once auth has resolved, which makes
  /// it the first honest place to ask.
  void _openLaunchUrlPage() {
    final path = AppRoutes.launchPageToOpen(
      Uri.base,
      AppRoutes.history.topRouteName,
    );
    if (path == null || _currentTool != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppRoutes.history.topRouteName == path) return;
      AppRoutes.navigatorKey.currentState?.pushNamed(path);
    });
  }

  @override
  void dispose() {
    _adminService.removeListener(_onAccessChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalCommandPaletteKey);
    // Guarded so a shell being replaced by a newer one doesn't clear the
    // newcomer's registration on its way out.
    if (identical(AppShell._active, this)) AppShell._active = null;
    super.dispose();
  }

  bool _handleGlobalCommandPaletteKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
    // Only act when the shell is the topmost route; a pushed editor/dialog has
    // its own handler and should win.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    _showCommandPalette();
    return true;
  }

  void _onAccessChanged() {
    if (!mounted) return;
    if (!AppDestinations.of(_currentScreen).isVisible && _currentTool == null) {
      _onScreenSelected(AppRoutes.defaultScreen);
    } else {
      setState(() {});
    }
  }

  WorkspaceInfo get _workspace => _currentTool == null
      ? AppWorkspaces.forScreen(_currentScreen)
      : AppWorkspaces.forTool(_currentTool!)!;

  void _onScreenSelected(DrawerScreen screen) {
    if (!AppDestinations.of(screen).isVisible) return;
    if (screen == _currentScreen && _currentTool == null) return;
    setState(() {
      _currentScreen = screen;
      _currentTool = null;
      _visitedScreens.add(screen);
      final info = AppWorkspaces.forScreen(screen);
      _lastEntries[info.workspace] = info.entries.firstWhere(
        (e) => e.screen == screen,
      );
    });
    AppRoutes.refresh();
  }

  void _onToolSelected(AppTool tool, {String? guideAnchor}) {
    final info = AppTools.of(tool);
    if (info.screen != null) {
      _onScreenSelected(info.screen!);
      return;
    }
    if (!info.isReachable ||
        (tool == _currentTool &&
            (tool != AppTool.guide || guideAnchor == _guideAnchor))) {
      return;
    }
    setState(() {
      _currentTool = tool;
      if (tool == AppTool.guide) _guideAnchor = guideAnchor;
      _visitedTools.add(tool);
      final workspace = AppWorkspaces.forTool(tool)!;
      _lastEntries[workspace.workspace] = workspace.entries.firstWhere(
        (e) => e.tool == tool,
      );
    });
    AppRoutes.refresh();
  }

  void _onEntrySelected(WorkspaceEntry entry) {
    if (entry.screen != null) {
      _onScreenSelected(entry.screen!);
    } else {
      _onToolSelected(entry.tool!);
    }
  }

  void _onWorkspaceSelected(AppWorkspace workspace) {
    if (workspace == _workspace.workspace) return;
    final entries = AppWorkspaces.of(workspace).visibleEntries;
    if (entries.isEmpty) return;
    final last = _lastEntries[workspace];
    _onEntrySelected(last != null && last.isVisible ? last : entries.first);
  }

  void _showCommandPalette() {
    CommandPalette.show(
      context,
      currentScreen: _currentTool == null ? _currentScreen : null,
      onNavigate: (screen) => _onScreenSelected(screen),
      onToggleTheme: () => ThemeSelectorDialog.show(context),
      onReplayTour: () {
        if (_currentTool != null ||
            !TutorialService().replayForScreen(context, _currentScreen)) {
          ToastService.showInfo('No guided tour for this page');
        }
      },
      onSignOut: () async {
        await AuthService().signOut();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ToastService.init(context);
    });
  }

  Widget _screenFor(DrawerScreen screen) {
    return switch (screen) {
      DrawerScreen.timetables => const TimetablesScreen(),
      DrawerScreen.calendar => const CalendarScreen(),
      DrawerScreen.freeSlotFinder => const FreeSlotFinderScreen(),
      DrawerScreen.cgpaCalculator => const CGPACalculatorScreen(),
      DrawerScreen.examSeating => const ExamSeatingScreen(),
      DrawerScreen.acadDrives => const AcadDrivesScreen(),
      DrawerScreen.profChambers => const ProfessorsScreen(),
      DrawerScreen.announcements => const CourseAnnouncementsScreen(),
      DrawerScreen.minors => const MinorsScreen(),
      DrawerScreen.faq => const FaqScreen(),
      DrawerScreen.bugReport => const BugReportScreen(),
      DrawerScreen.admin => DeferredScreen(
          load: admin_screen.loadLibrary,
          builder: () => admin_screen.AdminScreen(),
        ),
    };
  }

  Widget _buildIndexedStack() {
    final tools = AppTool.values
        .where(
          (tool) =>
              AppTools.of(tool).screen == null &&
              AppWorkspaces.forTool(tool) != null,
        )
        .toList();
    final currentIndex = _currentTool == null
        ? _allScreens.indexOf(_currentScreen)
        : _allScreens.length + tools.indexOf(_currentTool!);
    return IndexedStack(
      index: currentIndex,
      children: [
        for (final screen in _allScreens)
          if (_visitedScreens.contains(screen) &&
              AppDestinations.of(screen).isVisible)
            TickerMode(
              enabled: _currentTool == null && screen == _currentScreen,
              child: _screenFor(screen),
            )
          else
            const SizedBox.shrink(),
        for (final tool in tools)
          if (_visitedTools.contains(tool) &&
              AppTools.of(tool).isReachable &&
              (tool != AppTool.degreeAudit || tool == _currentTool))
            TickerMode(
              enabled: tool == _currentTool,
              child: tool == AppTool.guide
                  ? GuideScreen(
                      key: ValueKey(_guideAnchor),
                      embedded: true,
                      initialAnchor: _guideAnchor,
                    )
                  : AppTools.of(tool).build(null),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        child: WorkspaceFrame(
          workspace: _workspace,
          workspaces: AppWorkspaces.visible,
          entries: _workspace.visibleEntries,
          selectedId: _currentTool?.name ?? _currentScreen.name,
          onWorkspaceSelected: _onWorkspaceSelected,
          onEntrySelected: _onEntrySelected,
          onSearch: _showCommandPalette,
          onTheme: () => ThemeSelectorDialog.show(context),
          onProfile: isSignedIn()
              ? () => AppTools.of(AppTool.profile).pushOn(Navigator.of(context))
              : null,
          collapsed: _sidebarCollapsed,
          onToggleCollapse: () =>
              setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          child: _buildIndexedStack(),
        ),
      );
}
