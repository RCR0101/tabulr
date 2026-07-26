import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data/auth_service.dart';
import '../services/data/cgpa_service.dart';
import '../services/data/profile_service.dart';
import '../services/data/course_announcement_service.dart';
import '../services/ui/responsive_service.dart';
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
// Deferred: ~7k lines across screens/admin/ that only allowlisted accounts can
// open, otherwise compiled into the bundle every visitor downloads.
import '../screens/admin_screen.dart' deferred as admin_screen;
import '../screens/free_slot_finder_screen.dart';
import '../services/data/admin_service.dart';
import '../utils/app_routes.dart';
import 'common/deferred_screen.dart';
import 'app_destinations.dart';
import 'app_tools.dart';
import 'app_sidebar.dart';
import 'command_palette.dart';
import 'theme_selector_widget.dart';

/// Turns browser back/forward into a screen switch.
///
/// Must be registered on [WidgetsBinding] *before* `runApp`. The binding hands
/// a pushed route to each observer in registration order and stops at the first
/// one that returns true; `WidgetsApp` registers itself when it builds and, on
/// an app with no `routes:` table, answers by calling `pushNamed('/cgpa')` — a
/// route nothing generates. Getting in first is what keeps that from happening,
/// and is why this is a free-standing observer rather than the shell's own
/// State, which the framework would always reach second.
class AppRouteObserver with WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    await _applyUrl(routeInformation.uri);
    // Always handled: on web this app owns its whole URL space, and letting a
    // path fall through to WidgetsApp is precisely the pushNamed crash above.
    return true;
  }

  /// Makes the app match [uri] — the tab underneath and whatever is stacked on
  /// top of it. Called when the *browser* moved, so it must never write the URL
  /// back; the entry it would push is the one we just navigated to.
  Future<void> _applyUrl(Uri uri) async {
    final navigator = AppRoutes.navigatorKey.currentState;
    final page = AppRoutes.pageIn(uri);
    final history = AppRoutes.history;

    if (navigator != null &&
        navigator.canPop() &&
        history.topRouteName != page?.path) {
      // Something is stacked over the shell and the URL has stopped naming it,
      // so this Back is about closing that — never also about switching the tab
      // underneath. Doing both made one Back press do two navigations: the
      // Electives screen closed *and* the shell jumped to whatever tab the
      // consumed history entry happened to name.
      //
      // Screens pushed anonymously (the timetable editor, an Electives opened
      // from the editor with a selection link) never wrote a history entry, so
      // the entry being spent here belongs to something else. AppRouteHistory
      // .didPop puts the address bar back on the tab that is actually showing.
      if (history.isShowingPage) {
        navigator.pop();
      } else {
        // maybePop, so a `PopScope` — the editor's unsaved-changes prompt —
        // still gets to ask and refuse. A plain pop here would be a
        // back-button-shaped hole in that guard.
        await navigator.maybePop();
      }
      return;
    }

    if (page != null) {
      final path = page.path;
      if (path != null && history.topRouteName != path) {
        navigator?.pushNamed(path);
      }
      // The URL names a pushed screen, not a tab: leave the shell on whatever
      // it was showing, so closing that screen reveals where the user came from.
      return;
    }

    // Falls back rather than doing nothing: an unrecognised path means Back has
    // landed on `/` or on a share link. Ignoring it would leave the address bar
    // saying `/` while the CGPA screen is still showing.
    AppShell.goTo(
      AppRoutes.screenIn(uri) ?? AppRoutes.defaultScreen,
      updateUrl: false,
    );
  }
}

class AppShell extends StatefulWidget {
  final DrawerScreen initialScreen;

  const AppShell({
    super.key,
    this.initialScreen = AppRoutes.defaultScreen,
  });

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
  /// [updateUrl] is false when the browser is the one that moved (back button)
  /// — writing the URL back would push a second history entry for a navigation
  /// that already has one, and Back would then need two presses.
  static void goTo(DrawerScreen screen, {bool updateUrl = true}) =>
      _active?._onScreenSelected(screen, updateUrl: updateUrl);

  /// The tab the mounted shell is showing, or null when none is mounted.
  static DrawerScreen? get currentScreen => _active?._currentScreen;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late DrawerScreen _currentScreen;
  bool _sidebarCollapsed = false;
  final Set<DrawerScreen> _visitedScreens = {};

  static const _allScreens = DrawerScreen.values;

  @override
  void initState() {
    super.initState();
    // A deep link picks the opening tab. [Uri.base] tracks the live URL on web
    // rather than the landing one, so a shell rebuilt later (a sign-out and
    // back in) reopens wherever the user actually is.
    _currentScreen = AppRoutes.screenIn(Uri.base) ?? widget.initialScreen;
    _visitedScreens.add(_currentScreen);
    AppShell._active = this;
    _openLaunchUrlPage();
    // Handle Cmd/Ctrl+K at the keyboard level so it works regardless of where
    // focus currently sits — a focused CallbackShortcuts stops firing once focus
    // drifts off its subtree (tab switches, closed dialogs).
    HardwareKeyboard.instance.addHandler(_handleGlobalCommandPaletteKey);
    if (AuthService().isAuthenticated) {
      Future.delayed(const Duration(seconds: 2), () {
        CGPAService().prefetch();
      });
      // Load saved defaults so consumers (exam seating, CDC loader, …) can
      // read them synchronously.
      ProfileService().load();
    }
  }

  /// Opens the pushed screen the launch URL names, if it is not already open.
  ///
  /// Flutter generates the initial route from the browser path itself, so a
  /// *public* screen like `/credits` is already stacked over this shell by the
  /// time we get here — pushing it again put two copies on the stack and made
  /// the user close it twice. Hence the check rather than an unconditional
  /// push.
  ///
  /// The rest need this. Their routes are gated on being signed in, and that
  /// gate is read while `MaterialApp` builds its first frame — before Firebase
  /// Auth has restored the persisted web session, so `currentUser` is still
  /// null and Flutter drops the route. Cold-loading `/prerequisites` landed on
  /// the default tab even for a signed-in user. This shell only exists once
  /// auth has resolved, which makes it the first honest place to ask.
  void _openLaunchUrlPage() {
    final path =
        AppRoutes.launchPageToOpen(Uri.base, AppRoutes.history.topRouteName);
    if (path == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppRoutes.history.topRouteName == path) return;
      AppRoutes.navigatorKey.currentState?.pushNamed(path);
    });
  }

  @override
  void dispose() {
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

  void _onScreenSelected(DrawerScreen screen, {bool updateUrl = true}) {
    if (screen == _currentScreen) return;
    setState(() {
      _currentScreen = screen;
      _visitedScreens.add(screen);
    });
    if (updateUrl) AppRoutes.show(screen);
  }

  void _showCommandPalette() {
    CommandPalette.show(
      context,
      currentScreen: _currentScreen,
      onNavigate: (screen) => _onScreenSelected(screen),
      onToggleTheme: () => ThemeSelectorDialog.show(context),
      onReplayTour: () {
        if (!TutorialService().replayForScreen(context, _currentScreen)) {
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
    final currentIndex = _allScreens.indexOf(_currentScreen);
    return IndexedStack(
      index: currentIndex,
      children: _allScreens.map((screen) {
        if (!_visitedScreens.contains(screen)) return const SizedBox.shrink();
        return _screenFor(screen);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !ResponsiveService.isMobile(context);
    final isTablet = ResponsiveService.isTablet(context);

    Widget body;
    if (isDesktop) {
      body = Row(
        children: [
          AppSidebar(
            currentScreen: _currentScreen,
            onScreenSelected: _onScreenSelected,
            collapsed: isTablet || _sidebarCollapsed,
            onToggleCollapse: isTablet
                ? null
                : () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            onShowCommandPalette: _showCommandPalette,
          ),
          Expanded(child: _buildIndexedStack()),
        ],
      );
    } else {
      body = _MobileShell(
        currentScreen: _currentScreen,
        onScreenSelected: _onScreenSelected,
        onShowCommandPalette: _showCommandPalette,
        child: _buildIndexedStack(),
      );
    }

    return Focus(
      autofocus: true,
      child: body,
    );
  }
}

class _MobileShell extends StatelessWidget {
  final DrawerScreen currentScreen;
  final ValueChanged<DrawerScreen> onScreenSelected;
  final VoidCallback onShowCommandPalette;
  final Widget child;

  const _MobileShell({
    required this.currentScreen,
    required this.onScreenSelected,
    required this.onShowCommandPalette,
    required this.child,
  });

  static const _primaryTabs = [
    DrawerScreen.timetables,
    DrawerScreen.calendar,
    DrawerScreen.examSeating,
  ];

  // Bottom-nav indices for the two non-screen actions that follow the tabs.
  static const _searchIndex = 3;
  static const _moreIndex = 4;

  List<DrawerScreen> _overflowItems() {
    final auth = AuthService();
    final items = <DrawerScreen>[];
    if (auth.isAuthenticated) items.add(DrawerScreen.freeSlotFinder);
    if (auth.isAuthenticated) items.add(DrawerScreen.cgpaCalculator);
    if (auth.isAuthenticated) items.add(DrawerScreen.acadDrives);
    if (auth.isAuthenticated) items.add(DrawerScreen.profChambers);
    if (auth.isAuthenticated && CourseAnnouncementService().isHyderabadUser()) {
      items.add(DrawerScreen.announcements);
    }
    items.add(DrawerScreen.minors);
    items.add(DrawerScreen.faq);
    if (auth.isAuthenticated) items.add(DrawerScreen.bugReport);
    if (auth.isAuthenticated && AdminService().isAdmin) {
      items.add(DrawerScreen.admin);
    }
    return items;
  }

  int _currentIndex() {
    final idx = _primaryTabs.indexOf(currentScreen);
    // Screens reached via the "More" sheet keep that tab highlighted.
    return idx >= 0 ? idx : _moreIndex;
  }

  void _onTap(BuildContext context, int index) {
    if (index < _primaryTabs.length) {
      onScreenSelected(_primaryTabs[index]);
    } else if (index == _searchIndex) {
      // Search opens the palette as an overlay; it isn't a screen, so the
      // selected tab stays on whatever's currently showing.
      onShowCommandPalette();
    } else {
      _showMoreSheet(context);
    }
  }

  void _showMoreSheet(BuildContext context) {
    final overflow = _overflowItems();
    showModalBottomSheet(
      context: context,
      // Let the sheet grow to its content, capped below, so it can scroll
      // instead of the default 9/16 clamp forcing an overflow on short phones.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Scrolls only when the items don't fit (small phones); otherwise
              // Flexible shrinks to content and nothing scrolls. Handle stays pinned.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...overflow.map((screen) => ListTile(
                            leading: Icon(_iconFor(screen)),
                            title: Text(_labelFor(screen)),
                            selected: currentScreen == screen,
                            onTap: () {
                              Navigator.pop(ctx);
                              onScreenSelected(screen);
                            },
                          )),
                      const Divider(height: 1),
                      if (AuthService().isAuthenticated)
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: const Text('Profile'),
                          onTap: () {
                            Navigator.pop(ctx);
                            AppTools.of(AppTool.profile).pushOn(Navigator.of(context));
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Credits'),
                        onTap: () {
                          Navigator.pop(ctx);
                          AppTools.of(AppTool.credits).pushOn(Navigator.of(context));
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(DrawerScreen screen) => switch (screen) {
        DrawerScreen.timetables => Icons.schedule,
        DrawerScreen.calendar => Icons.calendar_month,
        DrawerScreen.freeSlotFinder => Icons.group,
        DrawerScreen.cgpaCalculator => Icons.calculate,
        DrawerScreen.examSeating => Icons.event_seat,
        DrawerScreen.acadDrives => Icons.folder_shared,
        DrawerScreen.profChambers => Icons.person,
        DrawerScreen.announcements => Icons.campaign,
        DrawerScreen.minors => Icons.workspace_premium_outlined,
        DrawerScreen.faq => Icons.help_outline,
        DrawerScreen.bugReport => Icons.bug_report_outlined,
        DrawerScreen.admin => Icons.admin_panel_settings,
      };

  /// Short label for the bottom nav, where width is tight.
  static String _navLabelFor(DrawerScreen screen) => switch (screen) {
        DrawerScreen.examSeating => 'Exams',
        _ => _labelFor(screen),
      };

  static String _labelFor(DrawerScreen screen) => switch (screen) {
        DrawerScreen.timetables => 'Timetables',
        DrawerScreen.calendar => 'Calendar',
        DrawerScreen.freeSlotFinder => 'Free Slots',
        DrawerScreen.cgpaCalculator => 'CGPA',
        DrawerScreen.examSeating => 'Exam Seating',
        DrawerScreen.acadDrives => 'Acad Drives',
        DrawerScreen.profChambers => 'Prof Chambers',
        DrawerScreen.announcements => 'Announcements',
        DrawerScreen.minors => 'Minors',
        DrawerScreen.faq => 'Academic FAQ',
        DrawerScreen.bugReport => 'Bug Report',
        DrawerScreen.admin => 'Admin',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = _currentIndex();

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => _onTap(context, i),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        destinations: [
          // Primary tabs are derived so this list and _primaryTabs can't drift
          // out of index alignment.
          for (final tab in _primaryTabs)
            NavigationDestination(
              icon: Icon(_iconFor(tab),
                  color: scheme.onSurface.withValues(alpha: 0.6)),
              selectedIcon: Icon(_iconFor(tab), color: scheme.primary),
              label: _navLabelFor(tab),
            ),
          NavigationDestination(
            icon: Icon(Icons.search, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.search, color: scheme.primary),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.more_horiz, color: scheme.primary),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
