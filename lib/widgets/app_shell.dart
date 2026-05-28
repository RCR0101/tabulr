import 'package:flutter/material.dart';
import '../services/data/auth_service.dart';
import '../services/data/course_announcement_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../screens/timetables_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/cgpa_calculator_screen.dart';
import '../screens/exam_seating_screen.dart';
import '../screens/acad_drives_screen.dart';
import '../screens/professors_screen.dart';
import '../screens/course_announcements_screen.dart';
import '../screens/free_slot_finder_screen.dart';
import 'app_drawer.dart';
import 'app_sidebar.dart';

class AppShell extends StatefulWidget {
  final DrawerScreen initialScreen;

  const AppShell({
    super.key,
    this.initialScreen = DrawerScreen.timetables,
  });

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
  }

  void _onScreenSelected(DrawerScreen screen) {
    if (screen == _currentScreen) return;
    setState(() {
      _currentScreen = screen;
      _visitedScreens.add(screen);
    });
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

    if (isDesktop) {
      return Row(
        children: [
          AppSidebar(
            currentScreen: _currentScreen,
            onScreenSelected: _onScreenSelected,
            collapsed: isTablet || _sidebarCollapsed,
            onToggleCollapse: isTablet
                ? null
                : () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          ),
          Expanded(child: _buildIndexedStack()),
        ],
      );
    }

    return _MobileShell(
      currentScreen: _currentScreen,
      onScreenSelected: _onScreenSelected,
      child: _buildIndexedStack(),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final DrawerScreen currentScreen;
  final ValueChanged<DrawerScreen> onScreenSelected;
  final Widget child;

  const _MobileShell({
    required this.currentScreen,
    required this.onScreenSelected,
    required this.child,
  });

  static const _primaryTabs = [
    DrawerScreen.timetables,
    DrawerScreen.calendar,
    DrawerScreen.examSeating,
  ];

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
    return items;
  }

  int _currentIndex() {
    final idx = _primaryTabs.indexOf(currentScreen);
    return idx >= 0 ? idx : 3;
  }

  void _onTap(BuildContext context, int index) {
    if (index < _primaryTabs.length) {
      onScreenSelected(_primaryTabs[index]);
    } else {
      _showMoreSheet(context);
    }
  }

  void _showMoreSheet(BuildContext context) {
    final overflow = _overflowItems();
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
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ...overflow.map((screen) => ListTile(
                  leading: Icon(_iconFor(screen)),
                  title: Text(_labelFor(screen)),
                  selected: currentScreen == screen,
                  onTap: () {
                    Navigator.pop(ctx);
                    onScreenSelected(screen);
                  },
                )),
            const SizedBox(height: 8),
          ],
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
            icon: Icon(Icons.more_horiz, color: scheme.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.more_horiz, color: scheme.primary),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
