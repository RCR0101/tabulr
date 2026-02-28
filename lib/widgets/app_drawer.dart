import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/responsive_service.dart';
import '../screens/timetables_screen.dart';
import '../screens/cgpa_calculator_screen.dart';
import '../screens/exam_seating_screen.dart';
import '../screens/acad_drives_screen.dart';
import '../screens/professors_screen.dart';

enum DrawerScreen {
  timetables,
  cgpaCalculator,
  examSeating,
  acadDrives,
  profChambers,
}

class AppDrawer extends StatelessWidget {
  final DrawerScreen currentScreen;
  final AuthService? authService;

  const AppDrawer({
    super.key,
    required this.currentScreen,
    this.authService,
  });

  @override
  Widget build(BuildContext context) {
    final auth = authService ?? AuthService();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(24),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.school,
                      size: ResponsiveService.getAdaptiveIconSize(context, 32),
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  SizedBox(
                    height: ResponsiveService.getAdaptiveSpacing(context, 12),
                  ),
                  Text(
                    'Tabulr',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView(
                padding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(vertical: 16),
                ),
                children: [
                  _buildMenuItem(
                    context: context,
                    icon: Icons.schedule,
                    title: 'TT Builder',
                    subtitle: 'Create timetables',
                    isSelected: currentScreen == DrawerScreen.timetables,
                    onTap: () => _navigateTo(
                      context,
                      DrawerScreen.timetables,
                    ),
                  ),

                  const Divider(),

                  // Show CGPA Calculator only if user is signed in
                  if (auth.isAuthenticated)
                    _buildMenuItem(
                      context: context,
                      icon: Icons.calculate,
                      title: 'CGPA Calculator',
                      subtitle: 'Track your academic performance',
                      isSelected: currentScreen == DrawerScreen.cgpaCalculator,
                      onTap: () => _navigateTo(
                        context,
                        DrawerScreen.cgpaCalculator,
                      ),
                    ),

                  _buildMenuItem(
                    context: context,
                    icon: Icons.event_seat,
                    title: 'Exam Seating',
                    subtitle: 'Find your Exam Hall',
                    isSelected: currentScreen == DrawerScreen.examSeating,
                    onTap: () => _navigateTo(
                      context,
                      DrawerScreen.examSeating,
                    ),
                  ),

                  if (auth.isAuthenticated)
                    _buildMenuItem(
                      context: context,
                      icon: Icons.folder_shared,
                      title: 'Academic Drives',
                      subtitle: 'Browse & share academic resources',
                      isSelected: currentScreen == DrawerScreen.acadDrives,
                      onTap: () => _navigateTo(
                        context,
                        DrawerScreen.acadDrives,
                      ),
                    ),

                  if (auth.isAuthenticated)
                    _buildMenuItem(
                      context: context,
                      icon: Icons.person,
                      title: 'Prof Chambers',
                      subtitle: 'Find professor offices',
                      isSelected: currentScreen == DrawerScreen.profChambers,
                      onTap: () => _navigateTo(
                        context,
                        DrawerScreen.profChambers,
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(16),
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: ResponsiveService.getAdaptiveIconSize(context, 16),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  SizedBox(
                    width: ResponsiveService.getAdaptiveSpacing(context, 8),
                  ),
                  Expanded(
                    child: Text(
                      'Made with ❤️ for students',
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(
                          context,
                          12,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface,
        size: ResponsiveService.getAdaptiveIconSize(context, 24),
      ),
      tileColor: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: isSelected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
          : null,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 16),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: ResponsiveService.getAdaptiveFontSize(context, 12),
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      onTap: onTap,
    );
  }

  void _navigateTo(BuildContext context, DrawerScreen screen) {
    Navigator.pop(context); // Close the drawer first

    if (screen == currentScreen) {
      return; // Already on this screen
    }

    Widget destination;
    switch (screen) {
      case DrawerScreen.timetables:
        destination = const TimetablesScreen();
        break;
      case DrawerScreen.cgpaCalculator:
        destination = const CGPACalculatorScreen();
        break;
      case DrawerScreen.examSeating:
        destination = const ExamSeatingScreen();
        break;
      case DrawerScreen.acadDrives:
        destination = const AcadDrivesScreen();
        break;
      case DrawerScreen.profChambers:
        destination = const ProfessorsScreen();
        break;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
  }
}
