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
import '../screens/admin_screen.dart';
import '../screens/free_slot_finder_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/profile_screen.dart';
import '../services/data/admin_service.dart';
import 'app_destinations.dart';
import 'app_sidebar.dart';
import 'command_palette.dart';
import 'theme_selector_widget.dart';

class AppShell extends StatefulWidget {
  final DrawerScreen initialScreen;

  const AppShell({
    super.key,
    this.initialScreen = DrawerScreen.timetables,
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
  static void goTo(DrawerScreen screen) => _active?._onScreenSelected(screen);

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
    _currentScreen = widget.initialScreen;
    _visitedScreens.add(_currentScreen);
    AppShell._active = this;
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

  void _onScreenSelected(DrawerScreen screen) {
    if (screen == _currentScreen) return;
    setState(() {
      _currentScreen = screen;
      _visitedScreens.add(screen);
    });
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
      DrawerScreen.admin => const AdminScreen(),
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ProfileScreen()),
                            );
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Credits'),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CreditsScreen()),
                          );
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
          NavigationDestination(
            icon: Icon(Icons.schedule, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.schedule, color: scheme.primary),
            label: 'Timetables',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.calendar_month, color: scheme.primary),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_seat, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.event_seat, color: scheme.primary),
            label: 'Exams',
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
