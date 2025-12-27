import 'package:flutter/material.dart';
import '../services/responsive_service.dart';
import '../services/auth_service.dart';
import '../screens/timetables_screen.dart';
import '../screens/cgpa_calculator_screen.dart';
import '../screens/acad_drives_screen.dart';

/// Enum to identify which screen is currently active
enum DrawerScreen {
  timetables,
  cgpaCalculator,
  academicDrives,
}

/// Reusable app drawer widget used across multiple screens
class AppDrawerWidget extends StatelessWidget {
  /// The currently active screen to highlight the appropriate menu item
  final DrawerScreen currentScreen;
  
  /// Whether to show the footer (only shown in main timetables screen)
  final bool showFooter;
  
  /// Auth service for checking authentication status
  final AuthService? authService;

  const AppDrawerWidget({
    super.key,
    required this.currentScreen,
    this.showFooter = false,
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
            _buildHeader(context),

            // Menu Items
            Expanded(
              child: ListView(
                padding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(vertical: 16),
                ),
                children: [
                  _buildMenuTile(
                    context: context,
                    icon: Icons.schedule,
                    title: 'TT Builder',
                    subtitle: 'Create timetables',
                    isActive: currentScreen == DrawerScreen.timetables,
                    onTap: () => _navigateToScreen(
                      context,
                      const TimetablesScreen(),
                      currentScreen != DrawerScreen.timetables,
                    ),
                  ),

                  const Divider(),

                  // Show CGPA Calculator only if user is signed in
                  if (auth.isAuthenticated)
                    _buildMenuTile(
                      context: context,
                      icon: Icons.calculate,
                      title: 'CGPA Calculator',
                      subtitle: _getSubtitleForScreen(DrawerScreen.cgpaCalculator),
                      isActive: currentScreen == DrawerScreen.cgpaCalculator,
                      onTap: () => _navigateToScreen(
                        context,
                        const CGPACalculatorScreen(),
                        currentScreen != DrawerScreen.cgpaCalculator,
                      ),
                    ),

                  if (auth.isAuthenticated)
                    _buildMenuTile(
                      context: context,
                      icon: Icons.folder_shared,
                      title: 'Academic Drives',
                      subtitle: _getSubtitleForScreen(DrawerScreen.academicDrives),
                      isActive: currentScreen == DrawerScreen.academicDrives,
                      onTap: () => _navigateToScreen(
                        context,
                        const AcadDrivesScreen(),
                        currentScreen != DrawerScreen.academicDrives,
                      ),
                    ),
                ],
              ),
            ),

            // Footer (only shown in timetables screen)
            if (showFooter) _buildFooter(context),
          ],
        ),
      ),
    );
  }

  /// Build the drawer header with app logo and title
  Widget _buildHeader(BuildContext context) {
    return Container(
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
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.school,
              size: ResponsiveService.getAdaptiveIconSize(context, 32),
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
          Text(
            'Tabulr',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual menu tiles
  Widget _buildMenuTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isActive 
            ? Theme.of(context).colorScheme.primary 
            : Theme.of(context).colorScheme.onSurface,
        size: ResponsiveService.getAdaptiveIconSize(context, 24),
      ),
      tileColor: isActive 
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: isActive 
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
      trailing: null,
      onTap: onTap,
    );
  }

  /// Build the footer section
  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: ResponsiveService.getAdaptiveIconSize(context, 16),
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          Expanded(
            child: Text(
              'Made with ❤️ for students',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 12),
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get appropriate subtitle for each screen
  String _getSubtitleForScreen(DrawerScreen screen) {
    switch (screen) {
      case DrawerScreen.timetables:
        return 'Create timetables';
      case DrawerScreen.cgpaCalculator:
        return 'Track your academic performance';
      case DrawerScreen.academicDrives:
        return 'Browse & share academic resources';
    }
  }

  /// Navigate to the specified screen
  void _navigateToScreen(BuildContext context, Widget screen, bool shouldNavigate) {
    Navigator.pop(context); // Close drawer first
    
    if (shouldNavigate) {
      if (currentScreen == DrawerScreen.timetables) {
        // From timetables screen, use push to other screens
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      } else {
        // From other screens, use pushReplacement
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      }
    }
    // If already on the current screen, just close the drawer
  }
}

/// Mixin to easily add drawer functionality to screens
mixin AppDrawerMixin<T extends StatefulWidget> on State<T> {
  /// Build the app drawer for the current screen
  Widget buildAppDrawer(DrawerScreen currentScreen, {bool showFooter = false}) {
    return AppDrawerWidget(
      currentScreen: currentScreen,
      showFooter: showFooter,
    );
  }
}