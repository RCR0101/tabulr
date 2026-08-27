import 'package:flutter/material.dart';
import '../services/data/admin_service.dart';
import '../services/data/auth_service.dart';
import '../services/data/course_announcement_service.dart';

/// The screens the shell can show. Declaration order is navigation order.
enum DrawerScreen {
  timetables,
  calendar,
  freeSlotFinder,
  cgpaCalculator,
  examSeating,
  acadDrives,
  profChambers,
  announcements,
  minors,
  faq,
  bugReport,
  admin,
}

/// `AuthService().isAuthenticated`, fail-closed.
///
/// The auth singletons reach for Firebase on construction, so asking before
/// Firebase is up throws. Everything gated on this shows the signed-out view in
/// that window, which is the right answer anyway — nobody is signed in yet.
bool isSignedIn() {
  try {
    return AuthService().isAuthenticated;
  } catch (_) {
    return false;
  }
}

/// Who a destination is for.
///
/// Kept as data rather than an `if` at each call site so the sidebar and the
/// command palette can't gate the same screen differently — they used to, and
/// nobody would notice until a guest saw an entry that led nowhere.
enum DestinationAccess { everyone, signedIn, hyderabad, admin }

/// One navigable screen, described once.
@immutable
class AppDestination {
  const AppDestination({
    required this.screen,
    required this.icon,
    required this.label,
    required this.slug,
    required this.description,
    this.access = DestinationAccess.signedIn,
  });

  final DrawerScreen screen;
  final IconData icon;

  /// The screen's URL path segment, e.g. `cgpa` for `tabulr.net/cgpa`.
  ///
  /// Lives here rather than in a separate route table because that table would
  /// be the fourth list keyed by [DrawerScreen] and the first one nothing
  /// forces you to update — the sidebar and the palette already drifted apart
  /// once for exactly that reason. Treat a slug as permanent once shipped: it
  /// is a public URL, and static pages and pasted links point at it.
  final String slug;

  /// Shown in the sidebar and as the command palette's title. One name per
  /// thing — the two used to disagree ("CGPA" vs "CGPA Calculator").
  final String label;

  /// The palette's subtitle. Also searched, so it carries the wording someone
  /// might type that isn't in [label].
  final String description;

  final DestinationAccess access;

  bool get isVisible {
    if (access == DestinationAccess.everyone) return true;
    if (!isSignedIn()) return false;
    try {
      return switch (access) {
        DestinationAccess.everyone || DestinationAccess.signedIn => true,
        DestinationAccess.hyderabad =>
          CourseAnnouncementService().isHyderabadUser(),
        DestinationAccess.admin => AdminService().isAdmin,
      };
    } catch (_) {
      // Same Firebase-not-up hazard as [isSignedIn]: fail closed rather than
      // letting the whole sidebar fall over.
      return false;
    }
  }
}

/// The single source of truth for the app's navigation surface.
///
/// The sidebar and the command palette both render from here. They used to each
/// keep their own list, which is how Minors and Academic FAQ shipped to the
/// sidebar but never reached the palette.
abstract final class AppDestinations {
  /// Exhaustive by construction: adding a [DrawerScreen] value stops the build
  /// until it is described here. That is the point — a test can be forgotten,
  /// a compile error cannot.
  static AppDestination of(DrawerScreen screen) => switch (screen) {
    DrawerScreen.timetables => const AppDestination(
      screen: DrawerScreen.timetables,
      slug: 'timetables',
      icon: Icons.schedule,
      label: 'Timetables',
      description: 'Build and manage your timetables',
      access: DestinationAccess.everyone,
    ),
    DrawerScreen.calendar => const AppDestination(
      screen: DrawerScreen.calendar,
      slug: 'calendar',
      icon: Icons.calendar_month,
      label: 'Calendar',
      description: 'Your week, exams and announcements in one view',
    ),
    DrawerScreen.freeSlotFinder => const AppDestination(
      screen: DrawerScreen.freeSlotFinder,
      slug: 'free-slots',
      icon: Icons.group,
      label: 'Free Time Finder',
      description: 'Find common free slots with friends',
    ),
    DrawerScreen.cgpaCalculator => const AppDestination(
      screen: DrawerScreen.cgpaCalculator,
      slug: 'cgpa',
      icon: Icons.calculate,
      label: 'CGPA',
      description: 'Calculate, plan and project your CGPA',
    ),
    DrawerScreen.examSeating => const AppDestination(
      screen: DrawerScreen.examSeating,
      slug: 'exam-seating',
      icon: Icons.event_seat,
      label: 'Exam Seating',
      description: 'Find your exam room from your student ID',
      access: DestinationAccess.everyone,
    ),
    DrawerScreen.acadDrives => const AppDestination(
      screen: DrawerScreen.acadDrives,
      slug: 'acad-drives',
      icon: Icons.folder_shared,
      label: 'Acad Drives',
      description: 'Course materials and resources',
    ),
    DrawerScreen.profChambers => const AppDestination(
      screen: DrawerScreen.profChambers,
      slug: 'professors',
      icon: Icons.person,
      label: 'Prof Chambers',
      description: 'Professor chambers, schedules and contacts',
    ),
    DrawerScreen.announcements => const AppDestination(
      screen: DrawerScreen.announcements,
      slug: 'announcements',
      icon: Icons.campaign,
      label: 'Announcements',
      description: 'Course announcements from your classmates',
      access: DestinationAccess.hyderabad,
    ),
    // Open to guests: the Bulletin is public, and someone deciding whether
    // to sign up benefits from it as much as a logged-in student.
    DrawerScreen.minors => const AppDestination(
      screen: DrawerScreen.minors,
      slug: 'minors',
      icon: Icons.workspace_premium_outlined,
      label: 'Minors',
      description: 'Browse minor programmes and track your progress',
      access: DestinationAccess.everyone,
    ),
    DrawerScreen.faq => const AppDestination(
      screen: DrawerScreen.faq,
      slug: 'faq',
      icon: Icons.help_outline,
      label: 'Academic FAQ',
      description: 'Rules on grades, attendance, registration and more',
      access: DestinationAccess.everyone,
    ),
    DrawerScreen.bugReport => const AppDestination(
      screen: DrawerScreen.bugReport,
      slug: 'bug-report',
      icon: Icons.bug_report_outlined,
      label: 'Bug Report',
      description: 'File and track bug reports',
    ),
    DrawerScreen.admin => const AppDestination(
      screen: DrawerScreen.admin,
      slug: 'admin',
      icon: Icons.admin_panel_settings,
      label: 'Admin',
      description: 'Admin panel',
      access: DestinationAccess.admin,
    ),
  };

  /// Every destination, in navigation order.
  static List<AppDestination> get all => [
    for (final screen in DrawerScreen.values) of(screen),
  ];

  /// Those the current user can reach.
  static List<AppDestination> get visible => [
    for (final destination in all)
      if (destination.isVisible) destination,
  ];
}
