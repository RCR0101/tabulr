import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;

import '../widgets/app_destinations.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_tools.dart';
import 'page_transitions.dart';

/// Maps between browser URLs and what the app is showing.
///
/// The shell is one `MaterialApp(home:)` over an `IndexedStack`, so its tabs
/// are not Navigator routes and cannot be named by `routes:`/`onGenerateRoute`
/// — pushing a route per tab would stack the shell on top of itself. Tab URLs
/// are therefore a projection of [DrawerScreen], written with
/// [SystemNavigator.routeInformationUpdated]; the pushed screens registered in
/// [AppTools] with a `segment` are ordinary named routes.
///
/// Anything else pushed over the shell stays deliberately unaddressable. The
/// timetable editor is the reason: it is guarded against leaving with unsaved
/// changes, so a URL that could push or pop it would be a way around that
/// guard, and it needs a timetable id a path does not carry.
abstract final class AppRoutes {
  /// `tabulr.net/s/<code>` — a shared timetable.
  static const String shareSegment = 's';

  /// Where `/` lands, and where any path this app doesn't recognise lands.
  static const DrawerScreen defaultScreen = DrawerScreen.timetables;

  static const String _fallbackOrigin = 'https://tabulr.net';

  /// The app's one Navigator, so URL changes arriving from the browser can pop
  /// and push without a [BuildContext].
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Tracks the topmost route's name, which is the only way to tell "the
  /// profile page is open" from "the editor is open" when reconciling a URL.
  static final AppRouteHistory history = AppRouteHistory();

  /// Set when the app was opened on a `/s/<code>` link, cleared by whoever
  /// acts on it. A static rather than a constructor argument because the shell
  /// is built by [AuthWrapper] several layers below `main`, and only after the
  /// auth state resolves — which may be long after the URL was read.
  static String? pendingShareCode;

  static String pathFor(DrawerScreen screen) =>
      '/${AppDestinations.of(screen).slug}';

  /// The URL of a pushed screen, e.g. `/electives`. Null for a tool that has no
  /// segment — it is a shell tab, or cannot be rebuilt from a path.
  static String? pathForTool(AppTool tool) => AppTools.of(tool).path;

  /// The pushed screen [uri] names, or null if it names something else or the
  /// current user can't open it.
  static AppToolInfo? pageIn(Uri uri) =>
      uri.pathSegments.length == 1 ? AppTools.byPath('/${uri.pathSegments.first}') : null;

  /// The pushed screen a launch URL names and that is not already open, or
  /// null when there is nothing to do.
  ///
  /// Split out from the shell because both halves are easy to get wrong. A
  /// public screen is already on the stack by now — Flutter generated it from
  /// the browser path — and pushing it again stacks two copies. A gated one is
  /// not, because its gate was read before Firebase Auth restored the session.
  static String? launchPageToOpen(Uri uri, String? topRouteName) {
    final path = pageIn(uri)?.path;
    return path == null || path == topRouteName ? null : path;
  }

  /// Builds the pushed screens, for both `Navigator.pushNamed` and the initial
  /// route Flutter generates from the launch URL.
  ///
  /// Returning null for an unreachable screen is what makes a signed-out
  /// visitor opening `/profile` land on the app instead: Flutter drops an
  /// initial route it cannot generate and falls back to `/`.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final info = AppTools.byPath(settings.name);
    if (info == null) return null;
    // No selection link: a path cannot carry one, so these always open in their
    // standalone mode.
    return FadeSlidePageRoute<void>(page: info.build(null), settings: settings);
  }

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

  /// Points the address bar at [screen].
  ///
  /// Not a history entry. A plain `Navigator` puts the web engine in
  /// single-entry mode from its own `initState`, and there every
  /// [SystemNavigator.routeInformationUpdated] *replaces* the current entry, so
  /// the back button leaves the site rather than walking the tabs.
  ///
  /// Switching to multi-entry afterwards looks like the fix and is not:
  /// measured, `selectMultiEntryHistory()` tears down the sentinel entry
  /// single-entry mode pushed at startup — with a `go(-1)` and a
  /// `replaceState` — and a page cold-loaded at `/credits` ends up on `/` a
  /// second later. Correct URLs are worth more than the back button, so this
  /// stays in single-entry mode. Real history needs `MaterialApp.router`, which
  /// selects multi-entry before anything sets up single-entry.
  ///
  /// [replace] is accepted for intent even though the engine ignores it here —
  /// see [AppRouteHistory.didPop].
  /// Points the address bar at [screen], adding a history entry so Back works.
  ///
  static void show(DrawerScreen screen, {bool replace = false}) {
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(pathFor(screen)),
      replace: replace,
    );
  }
}

/// Watches the Navigator so the rest of the routing code knows what is on top.
class AppRouteHistory extends NavigatorObserver {
  /// The topmost route's name: a registered screen's path when one is open,
  /// `'/'` for the shell, and null for a route pushed without settings — the
  /// timetable editor, and every dialog, menu and bottom sheet.
  String? topRouteName;

  /// Whether [name] belongs to a route this app gave a URL to.
  ///
  /// Access is deliberately not consulted: this answers "did that route own an
  /// address", which stays true for a screen whose gate closed mid-session.
  static bool isAddressable(String? name) =>
      name != null && AppTools.all.any((info) => info.path == name);

  /// True when the topmost route is one [AppRoutes] put there, and so is safe
  /// to close without asking. Anything else may carry a `PopScope` guard.
  bool get isShowingPage => isAddressable(topRouteName);

  /// Whether popping [route] leaves the address bar lying about where the user
  /// is, and so needs [AppRoutes.show] to correct it.
  ///
  /// True only when an addressable screen closes back onto the shell. The
  /// checks are not redundant:
  ///
  ///  * Unaddressable routes never wrote a URL, so there is nothing to restore.
  ///    Correcting for them was a real bug — picking an item from the Tools
  ///    `PopupMenuButton` pops the menu route first, which scheduled a
  ///    correction that then landed *after* the screen the user picked was
  ///    pushed, and put the address bar straight back on `/timetables`.
  ///  * Landing on another pushed screen needs nothing either: the Navigator
  ///    announces the name of whatever it uncovers, and that name is right.
  static bool needsUrlRestore(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      isAddressable(route.settings.name) && previousRoute?.isFirst == true;

  void _update(Route<dynamic>? route) => topRouteName = route?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final restore = needsUrlRestore(route, previousRoute);
    _update(previousRoute);
    if (!restore) return;
    // Back at the shell. The Navigator announces the route it uncovered, which
    // is `home` — named `/` — so without this the address bar would read `/`
    // while some other tab is showing. Corrected after the frame because that
    // announcement happens later in the same flush, and in place because
    // closing a screen is not a new destination.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screen = AppShell.currentScreen;
      if (screen != null) AppRoutes.show(screen, replace: true);
    });
  }
}
