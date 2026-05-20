import 'package:flutter/material.dart';
import '../services/responsive_service.dart';
import '../services/toast_service.dart';
import '../screens/timetables_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/cgpa_calculator_screen.dart';
import '../screens/exam_seating_screen.dart';
import '../screens/acad_drives_screen.dart';
import '../screens/professors_screen.dart';
import '../screens/course_announcements_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _currentScreen = widget.initialScreen;
  }

  Widget _buildScreen() {
    return switch (_currentScreen) {
      DrawerScreen.timetables => const TimetablesScreen(),
      DrawerScreen.calendar => const CalendarScreen(),
      DrawerScreen.cgpaCalculator => const CGPACalculatorScreen(),
      DrawerScreen.examSeating => const ExamSeatingScreen(),
      DrawerScreen.acadDrives => const AcadDrivesScreen(),
      DrawerScreen.profChambers => const ProfessorsScreen(),
      DrawerScreen.announcements => const CourseAnnouncementsScreen(),
    };
  }

  void _onScreenSelected(DrawerScreen screen) {
    if (screen == _currentScreen) return;
    setState(() => _currentScreen = screen);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ToastService.init(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !ResponsiveService.isMobile(context);

    if (isDesktop) {
      return Row(
        children: [
          AppSidebar(
            currentScreen: _currentScreen,
            onScreenSelected: _onScreenSelected,
            collapsed: _sidebarCollapsed,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          ),
          Expanded(child: _buildScreen()),
        ],
      );
    }

    // Mobile: use drawer-based navigation
    return _MobileShell(
      currentScreen: _currentScreen,
      onScreenSelected: _onScreenSelected,
      child: _buildScreen(),
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

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
