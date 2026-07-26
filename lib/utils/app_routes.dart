import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;

import '../widgets/app_destinations.dart';

/// Maps between browser URLs and the shell's screens.
///
/// The app is one `MaterialApp(home:)` over an `IndexedStack`, not a Navigator
/// stack, so there is nothing for `routes:`/`onGenerateRoute` to name — pushing
/// a route per screen would stack the shell on top of itself. Instead the URL
/// is treated as a projection of [DrawerScreen]: changing screen rewrites the
/// address bar, and the browser's back button feeds a URL back in.
///
/// Deliberately covers only the shell's screens and share links. Routes pushed
/// *on top* of the shell — the timetable editor above all — stay unaddressable:
/// the editor is guarded against leaving with unsaved changes, and a back
/// button that popped it would walk straight past that guard.
abstract final class AppRoutes {
  /// `tabulr.net/s/<code>` — a shared timetable.
  static const String shareSegment = 's';

  /// Where `/` lands, and where any path this app doesn't recognise lands.
  static const DrawerScreen defaultScreen = DrawerScreen.timetables;

  static const String _fallbackOrigin = 'https://tabulr.net';

  /// Set when the app was opened on a `/s/<code>` link, cleared by whoever
  /// acts on it. A static rather than a constructor argument because the shell
  /// is built by [AuthWrapper] several layers below `main`, and only after the
  /// auth state resolves — which may be long after the URL was read.
  static String? pendingShareCode;

  static String pathFor(DrawerScreen screen) =>
      '/${AppDestinations.of(screen).slug}';

  /// Absolute, because this is meant to be pasted into a chat.
  static String shareUrl(String code) =>
      '${kIsWeb ? Uri.base.origin : _fallbackOrigin}/$shareSegment/$code';

  /// The screen [uri] names, or null if it names something else.
  ///
  /// Returns null for a destination the current user cannot reach, so a stale
  /// `/admin` link lands on the default screen rather than an empty one.
  static DrawerScreen? screenIn(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 1) return null;
    for (final destination in AppDestinations.all) {
      if (destination.slug == segments.first) {
        return destination.isVisible ? destination.screen : null;
      }
    }
    return null;
  }

  /// The share code in [uri] (`/s/<code>`), or null.
  static String? shareCodeIn(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments.first != shareSegment) return null;
    final code = segments[1].trim();
    return code.isEmpty ? null : code;
  }

  /// The share code in whatever a user pasted — a full link, a bare code, or
  /// either with stray whitespace. Null if there is nothing usable.
  ///
  /// Now that sharing hands out links, "paste the code" is the *unusual* case:
  /// a field that only accepted a bare code would reject the very thing the app
  /// told the sender to copy.
  static String? shareCodeInText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.length > 1) return shareCodeIn(uri);
    return trimmed;
  }

  /// Points the address bar at [screen], adding a history entry so Back works.
  ///
  /// [SystemNavigator.routeInformationUpdated] is also what switches the web
  /// engine out of its single-entry history mode, which is what makes Back
  /// return here instead of leaving the site.
  static void show(DrawerScreen screen) {
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(uri: Uri.parse(pathFor(screen)));
  }
}
