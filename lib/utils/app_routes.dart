import 'dart:async' show scheduleMicrotask;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture, kIsWeb;

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

  static String get origin => kIsWeb ? Uri.base.origin : _fallbackOrigin;

  /// Absolute, because this is meant to be pasted into a chat.
  static String shareUrl(String code) => '$origin/$shareSegment/$code';

  /// The screen [uri] names, or null if it names something else.
  ///
  /// Returns null for a destination the current user cannot reach, so a stale
  /// `/admin` link lands on the default screen rather than an empty one.
  static DrawerScreen? screenIn(Uri uri) {
    final screen = screenNamedIn(uri);
    if (screen == null) return null;
    return AppDestinations.of(screen).isVisible ? screen : null;
  }

  /// The screen [uri] names by slug, whether or not this user can open it.
  static DrawerScreen? screenNamedIn(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 1) return null;
    for (final destination in AppDestinations.all) {
      if (destination.slug == segments.first) return destination.screen;
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

  /// What the address bar should say right now.
  ///
  /// A pushed screen wins over the tab underneath it, because that is what the
  /// user is looking at. Falling back to the live URL — rather than to `/` —
  /// matters before a shell exists: a visitor who followed `/exam-seating`
  /// spends the whole sign-in wall with no shell mounted, and reporting `/`
  /// would erase the link they arrived on.
  static Uri get currentUri {
    final page = history.addressablePath;
    if (page != null) return Uri.parse(page);
    final screen = AppShell.currentScreen;
    if (screen != null) return Uri.parse(pathFor(screen));
    return kIsWeb ? Uri(path: Uri.base.path) : Uri(path: '/');
  }

  /// The one router delegate, built around [home] the first time it is asked
  /// for. `MaterialApp` rebuilds on every theme change; the delegate must not.
  static AppRouterDelegate delegateFor(Widget home) =>
      _delegate ??= AppRouterDelegate(home: home);
  static AppRouterDelegate? _delegate;

  static bool _refreshScheduled = false;

  /// Tells the Router the app has moved, so it re-reads [currentUri] and writes
  /// the address bar.
  ///
  /// Deferred to a microtask because the callers are `NavigatorObserver`
  /// hooks and `setState`, which run mid-frame; [Router] answers by calling
  /// `setState` on itself, which is illegal during a build. Coalesced because
  /// one gesture can move several things at once.
  static void refresh() {
    if (_refreshScheduled || _delegate == null) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      _delegate?.refresh();
    });
  }

  /// Makes the app match [uri]. Called when the *browser* moved — a back or
  /// forward press — so it must never write the URL back; the entry it would
  /// push is the one just navigated to.
  static Future<void> applyUrl(Uri uri) async {
    final navigator = navigatorKey.currentState;
    final page = pageIn(uri);

    if (navigator != null &&
        navigator.canPop() &&
        history.topRouteName != page?.path) {
      // Something is stacked over the shell and the URL has stopped naming it,
      // so this Back is about closing that — never also about switching the tab
      // underneath. Doing both made one Back press do two navigations: the
      // Electives screen closed *and* the shell jumped to whatever tab the
      // consumed history entry happened to name.
      if (history.isShowingPage) {
        navigator.pop();
      } else if (!await navigator.maybePop()) {
        // maybePop, so a `PopScope` — the editor's unsaved-changes prompt —
        // still gets to ask and refuse. A plain pop here would be a
        // back-button-shaped hole in that guard.
        //
        // Refused: the browser has already moved, so the address bar is now
        // naming a screen the user was not allowed to leave for. Put it back.
        refresh();
      }
      return;
    }

    if (page != null) {
      final path = page.path;
      if (path != null && history.topRouteName != path) {
        navigator?.pushNamed(path);
      }
      // The URL names a pushed screen, not a tab: leave the shell on whatever
      // it was showing, so closing that screen reveals where the user came from.
      return;
    }

    // Falls back rather than doing nothing: an unrecognised path means Back has
    // landed on `/` or on a share link. Ignoring it would leave the address bar
    // saying `/` while the CGPA screen is still showing.
    AppShell.goTo(screenIn(uri) ?? defaultScreen);
  }
}

/// Turns route information into a plain [Uri] and back. This app's URLs are
/// paths, so there is nothing else to parse.
class AppRouteInformationParser extends RouteInformationParser<Uri> {
  const AppRouteInformationParser();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture<Uri>(routeInformation.uri);

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      RouteInformation(uri: configuration);
}

/// Owns the app's Navigator and reports where it is to the browser.
///
/// The reason for using [Router] at all is the browser's back button. A plain
/// `MaterialApp(home:)` builds its Navigator with `reportsRouteUpdateToEngine`,
/// which puts the web engine in single-entry history mode: every URL update
/// *replaces* the current entry, so Back leaves the site instead of walking
/// back through the app. Selecting multi-entry mode later does not fix it — it
/// tears down the sentinel entry single-entry mode already pushed, with a
/// `go(-1)` and a `replaceState`, and a page cold-loaded at `/credits` lands on
/// `/` a second later. [Router] is the only way in: its
/// [PlatformRouteInformationProvider] selects multi-entry with every report,
/// and no Navigator ever asks for single-entry.
///
/// The Navigator below stays imperative — one page, everything else pushed.
/// A page list would have to enumerate the timetable editor, which is guarded
/// against leaving with unsaved changes and needs an id no path carries.
class AppRouterDelegate extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  AppRouterDelegate({required this.home});

  final Widget home;

  @override
  GlobalKey<NavigatorState> get navigatorKey => AppRoutes.navigatorKey;

  @override
  Uri get currentConfiguration => AppRoutes.currentUri;

  void refresh() => notifyListeners();

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        initialRoute: Navigator.defaultRouteName,
        observers: [AppRoutes.history],
        onGenerateRoute: (settings) =>
            settings.name == Navigator.defaultRouteName
                ? MaterialPageRoute<void>(
                    builder: (_) => home, settings: settings)
                : AppRoutes.onGenerateRoute(settings),
      );

  @override
  Future<void> setNewRoutePath(Uri configuration) =>
      AppRoutes.applyUrl(configuration);

  @override
  Future<void> setInitialRoutePath(Uri configuration) async {
    // After the frame: the Navigator this wants to push onto is built by the
    // very first call to [build], which has not happened yet.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => AppRoutes.applyUrl(configuration));
  }
}

/// Watches the Navigator so the rest of the routing code knows what is on top.
///
/// Keeps the whole stack rather than just its top, because the two questions
/// asked of it have different answers. "Can Back close this without asking?" is
/// about the topmost route. "What should the address bar say?" is about the
/// topmost route that *owns* an address — a dialog opened over Electives is on
/// top, and the URL must go on saying `/electives` while it is.
class AppRouteHistory extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// The topmost route's name: a registered screen's path when one is open,
  /// `'/'` for the shell, and null for a route pushed without settings — the
  /// timetable editor, and every dialog, menu and bottom sheet.
  String? get topRouteName =>
      _stack.isEmpty ? null : _stack.last.settings.name;

  /// The path of the nearest route to the top that has one, or null when only
  /// the shell and unaddressable routes are open.
  String? get addressablePath {
    for (final route in _stack.reversed) {
      final name = route.settings.name;
      if (isAddressable(name)) return name;
    }
    return null;
  }

  /// Whether [name] belongs to a route this app gave a URL to.
  ///
  /// Access is deliberately not consulted: this answers "did that route own an
  /// address", which stays true for a screen whose gate closed mid-session.
  static bool isAddressable(String? name) =>
      name != null && AppTools.all.any((info) => info.path == name);

  /// True when the topmost route is one [AppRoutes] put there, and so is safe
  /// to close without asking. Anything else may carry a `PopScope` guard.
  bool get isShowingPage => isAddressable(topRouteName);

  void _changed() => AppRoutes.refresh();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _changed();
  }

  void _drop(Route<dynamic> route) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (at < 0) return;
    if (newRoute == null) {
      _stack.removeAt(at);
    } else {
      _stack[at] = newRoute;
    }
    _changed();
  }
}
