import 'package:flutter/material.dart';
import '../models/timetable_selection_link.dart';
import '../screens/profile_screen.dart';
import '../utils/page_transitions.dart';
import '../screens/electives_screen.dart';
import '../screens/course_guide_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/minors_screen.dart';
import '../screens/prerequisites_screen.dart';
import '../screens/professors_screen.dart';
import '../screens/timetable_comparison_screen.dart';
import 'app_destinations.dart';

/// Screens reached by pushing a route rather than switching the shell.
enum AppTool {
  courseGuide,
  prerequisites,
  electives,
  minors,
  profChambers,
  compareTimetables,
  credits,
  profile,
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
    this.segment,
    this.signedInOnly = true,
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

  /// URL path segment, when this screen is worth addressing: `/electives`.
  ///
  /// Null for the two tools that are also shell destinations — those already
  /// have a slug on [AppDestination], and one screen with two URLs is a way to
  /// split its own search ranking — and for anything that cannot be rebuilt
  /// from a path alone.
  ///
  /// A segment is a public URL: permanent once shipped.
  final String? segment;

  /// Whether the screen is meaningless, or empty, to a signed-out visitor.
  /// Gates both the deep link and the palette entry.
  final bool signedInOnly;

  String? get path => segment == null ? null : '/$segment';

  bool get isReachable => !signedInOnly || isSignedIn();

  /// Opens this screen.
  ///
  /// Named — so it gets a URL and its own browser history entry — unless there
  /// is a [link] to carry. A selection link is bound to the timetable being
  /// edited and cannot be reconstructed from a path, so those pushes stay
  /// anonymous and the address bar keeps naming the editor's own screen.
  Future<void> pushOn(NavigatorState navigator, [TimetableSelectionLink? link]) {
    final named = path;
    if (link == null && named != null) return navigator.pushNamed(named);
    return navigator.push(FadeSlidePageRoute<void>(page: build(link)));
  }
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
            segment: 'course-guide',
            build: (_) => const CourseGuideScreen(),
          ),
        AppTool.prerequisites => AppToolInfo(
            tool: tool,
            icon: Icons.account_tree,
            label: 'Prerequisites',
            description: 'View course prerequisite chains',
            inEditorMenu: true,
            segment: 'prerequisites',
            build: (_) => const PrerequisitesScreen(),
          ),
        AppTool.electives => AppToolInfo(
            tool: tool,
            icon: Icons.school,
            label: 'Electives',
            description:
                'Browse discipline, humanities and open electives in one place',
            inEditorMenu: true,
            segment: 'electives',
            build: (link) => ElectivesScreen(selectionLink: link),
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
            segment: 'compare',
            build: (_) => const TimetableComparisonScreen(),
          ),
        AppTool.credits => AppToolInfo(
            tool: tool,
            icon: Icons.info_outline,
            label: 'Credits',
            description: 'About Tabulr and the people behind it',
            segment: 'credits',
            signedInOnly: false,
            build: (_) => const CreditsScreen(),
          ),
        AppTool.profile => AppToolInfo(
            tool: tool,
            icon: Icons.badge_outlined,
            label: 'Profile',
            description: 'Your ID, branch & semester defaults',
            segment: 'profile',
            build: (_) => const ProfileScreen(),
          ),
      };

  static List<AppToolInfo> get all =>
      [for (final tool in AppTool.values) of(tool)];

  static List<AppToolInfo> get editorMenu =>
      [for (final info in all) if (info.inEditorMenu) info];

  /// The tool a URL path names, or null. Unreachable tools resolve to null so a
  /// stale link opens the app rather than an empty screen.
  static AppToolInfo? byPath(String? path) {
    if (path == null) return null;
    for (final info in all) {
      if (info.path == path) return info.isReachable ? info : null;
    }
    return null;
  }

  static AppTool? byName(String name) {
    for (final tool in AppTool.values) {
      if (tool.name == name) return tool;
    }
    return null;
  }
}
