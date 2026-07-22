import 'package:flutter/material.dart';
import '../models/timetable_selection_link.dart';
import '../screens/course_guide_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/discipline_electives_screen.dart';
import '../screens/humanities_electives_screen.dart';
import '../screens/minors_screen.dart';
import '../screens/prerequisites_screen.dart';
import '../screens/professors_screen.dart';
import '../screens/timetable_comparison_screen.dart';
import 'app_destinations.dart';

/// Screens reached by pushing a route rather than switching the shell.
enum AppTool {
  courseGuide,
  prerequisites,
  disciplineElectives,
  humanitiesElectives,
  minors,
  profChambers,
  compareTimetables,
  credits,
}

@immutable
class AppToolInfo {
  const AppToolInfo({
    required this.tool,
    required this.icon,
    required this.label,
    required this.description,
    required this.build,
    this.inEditorMenu = false,
    this.screen,
  });

  final AppTool tool;
  final IconData icon;
  final String label;
  final String description;

  /// [link] is non-null only from the editor; tools that can add sections use
  /// it, the rest ignore it.
  final Widget Function(TimetableSelectionLink? link) build;

  /// Listed in the editor's Tools menu.
  final bool inEditorMenu;

  /// Set when this screen is also a shell destination, so the palette doesn't
  /// list it twice.
  final DrawerScreen? screen;
}

/// Single source for the editor's Tools menu and the command palette's tool
/// entries.
abstract final class AppTools {
  /// Exhaustive: a new [AppTool] stops the build until it is described here.
  static AppToolInfo of(AppTool tool) => switch (tool) {
        AppTool.courseGuide => AppToolInfo(
            tool: tool,
            icon: Icons.menu_book,
            label: 'Course Guide',
            description: 'Browse CDCs and electives by branch',
            inEditorMenu: true,
            build: (_) => const CourseGuideScreen(),
          ),
        AppTool.prerequisites => AppToolInfo(
            tool: tool,
            icon: Icons.account_tree,
            label: 'Prerequisites',
            description: 'View course prerequisite chains',
            inEditorMenu: true,
            build: (_) => const PrerequisitesScreen(),
          ),
        AppTool.disciplineElectives => AppToolInfo(
            tool: tool,
            icon: Icons.school,
            label: 'Discipline Electives',
            description: 'Browse and add discipline electives',
            inEditorMenu: true,
            build: (link) => DisciplineElectivesScreen(selectionLink: link),
          ),
        AppTool.humanitiesElectives => AppToolInfo(
            tool: tool,
            icon: Icons.library_books,
            label: 'Humanities Electives',
            description: 'Browse and add humanities electives',
            inEditorMenu: true,
            build: (link) => HumanitiesElectivesScreen(selectionLink: link),
          ),
        AppTool.minors => AppToolInfo(
            tool: tool,
            icon: Icons.workspace_premium_outlined,
            label: 'Minors',
            description: 'Browse minor programmes and track your progress',
            inEditorMenu: true,
            screen: DrawerScreen.minors,
            build: (link) => MinorsScreen(selectionLink: link),
          ),
        AppTool.profChambers => AppToolInfo(
            tool: tool,
            icon: Icons.person_search,
            label: 'Prof Chambers',
            description: 'Professor chambers, schedules and contacts',
            inEditorMenu: true,
            screen: DrawerScreen.profChambers,
            build: (link) => ProfessorsScreen(selectionLink: link),
          ),
        AppTool.compareTimetables => AppToolInfo(
            tool: tool,
            icon: Icons.compare,
            label: 'Compare Timetables',
            description: 'Side-by-side timetable comparison',
            build: (_) => const TimetableComparisonScreen(),
          ),
        AppTool.credits => AppToolInfo(
            tool: tool,
            icon: Icons.info_outline,
            label: 'Credits',
            description: 'About Tabulr and the people behind it',
            build: (_) => const CreditsScreen(),
          ),
      };

  static List<AppToolInfo> get all =>
      [for (final tool in AppTool.values) of(tool)];

  static List<AppToolInfo> get editorMenu =>
      [for (final info in all) if (info.inEditorMenu) info];

  static AppTool? byName(String name) {
    for (final tool in AppTool.values) {
      if (tool.name == name) return tool;
    }
    return null;
  }
}
