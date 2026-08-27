import 'package:flutter/material.dart';
import 'app_destinations.dart';
import 'app_tools.dart';

enum AppWorkspace { timetables, degree, calendar, explore, exams, help, admin }

/// Presentation groups only: access and permanent URLs still belong to each
/// feature. A public catalogue must not inherit a private neighbour's gate.
@immutable
class WorkspaceEntry {
  const WorkspaceEntry.screen(this.screen, this.label) : tool = null;
  const WorkspaceEntry.tool(this.tool, this.label) : screen = null;

  final DrawerScreen? screen;
  final AppTool? tool;
  final String label;

  String get id => screen?.name ?? tool!.name;
  bool get isVisible =>
      screen != null
          ? AppDestinations.of(screen!).isVisible
          : AppTools.of(tool!).isReachable;
  IconData get icon =>
      screen != null
          ? AppDestinations.of(screen!).icon
          : AppTools.of(tool!).icon;
}

@immutable
class WorkspaceInfo {
  const WorkspaceInfo(this.workspace, this.label, this.icon, this.entries);
  final AppWorkspace workspace;
  final String label;
  final IconData icon;
  final List<WorkspaceEntry> entries;
  List<WorkspaceEntry> get visibleEntries =>
      entries.where((entry) => entry.isVisible).toList();
}

abstract final class AppWorkspaces {
  static const primary = [
    AppWorkspace.timetables,
    AppWorkspace.degree,
    AppWorkspace.calendar,
    AppWorkspace.explore,
    AppWorkspace.exams,
  ];

  static const all = [
    WorkspaceInfo(
      AppWorkspace.timetables,
      'Timetables',
      Icons.view_week_outlined,
      [
        WorkspaceEntry.screen(DrawerScreen.timetables, 'My timetables'),
        WorkspaceEntry.tool(AppTool.sampleTimetables, 'Samples'),
      ],
    ),
    WorkspaceInfo(AppWorkspace.degree, 'Degree', Icons.school_outlined, [
      WorkspaceEntry.screen(DrawerScreen.cgpaCalculator, 'Grades & targets'),
      WorkspaceEntry.tool(AppTool.courseGuide, 'Curriculum'),
      WorkspaceEntry.tool(AppTool.electives, 'Electives'),
      WorkspaceEntry.screen(DrawerScreen.minors, 'Minors'),
      WorkspaceEntry.tool(AppTool.degreeAudit, 'Audit'),
    ]),
    WorkspaceInfo(
      AppWorkspace.calendar,
      'Calendar',
      Icons.calendar_today_outlined,
      [
        WorkspaceEntry.screen(DrawerScreen.calendar, 'My week'),
        WorkspaceEntry.screen(DrawerScreen.freeSlotFinder, 'Availability'),
        WorkspaceEntry.screen(DrawerScreen.announcements, 'Updates'),
      ],
    ),
    WorkspaceInfo(AppWorkspace.explore, 'Explore', Icons.explore_outlined, [
      WorkspaceEntry.screen(DrawerScreen.acadDrives, 'Acad Drives'),
      WorkspaceEntry.tool(AppTool.prerequisites, 'Prerequisites'),
      WorkspaceEntry.screen(DrawerScreen.profChambers, 'Faculty'),
      WorkspaceEntry.tool(AppTool.courseHistory, 'Course History'),
    ]),
    WorkspaceInfo(AppWorkspace.exams, 'Exams', Icons.event_seat_outlined, [
      WorkspaceEntry.screen(DrawerScreen.examSeating, 'Exam seating'),
    ]),
    WorkspaceInfo(
      AppWorkspace.help,
      'Help & support',
      Icons.help_outline_rounded,
      [
        WorkspaceEntry.tool(AppTool.guide, 'Using Tabulr'),
        WorkspaceEntry.screen(DrawerScreen.faq, 'Academic rules'),
        WorkspaceEntry.screen(DrawerScreen.bugReport, 'Report a problem'),
        WorkspaceEntry.tool(AppTool.credits, 'About'),
      ],
    ),
    WorkspaceInfo(
      AppWorkspace.admin,
      'Admin',
      Icons.admin_panel_settings_outlined,
      [WorkspaceEntry.screen(DrawerScreen.admin, 'Administration')],
    ),
  ];

  static WorkspaceInfo of(AppWorkspace workspace) =>
      all.firstWhere((info) => info.workspace == workspace);

  static WorkspaceInfo forScreen(DrawerScreen screen) => all.firstWhere(
    (info) => info.entries.any((entry) => entry.screen == screen),
  );

  static WorkspaceInfo? forTool(AppTool tool) {
    final screen = AppTools.of(tool).screen;
    if (screen != null) return forScreen(screen);
    for (final info in all) {
      if (info.entries.any((entry) => entry.tool == tool)) return info;
    }
    return null;
  }

  static String contextForScreen(DrawerScreen screen) {
    final info = forScreen(screen);
    final entry = info.entries.firstWhere((entry) => entry.screen == screen);
    return [info.label, entry.label].join(' / ');
  }

  static String? contextForTool(AppTool tool) {
    final screen = AppTools.of(tool).screen;
    if (screen != null) return contextForScreen(screen);
    final info = forTool(tool);
    if (info == null) return null;
    final entry = info.entries.firstWhere((entry) => entry.tool == tool);
    return [info.label, entry.label].join(' / ');
  }

  static List<WorkspaceInfo> get visible =>
      all.where((info) => info.visibleEntries.isNotEmpty).toList();
}
