import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/app_routes.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';
import 'package:timetable_maker/widgets/app_tools.dart';

void main() {
  group('AppRoutes.screenIn', () {
    test('resolves a public destination by its slug', () {
      expect(AppRoutes.screenIn(Uri.parse('https://tabulr.net/exam-seating')),
          DrawerScreen.examSeating);
      expect(AppRoutes.screenIn(Uri.parse('/minors')), DrawerScreen.minors);
    });

    test('ignores a destination the current user cannot reach', () {
      // No Firebase in a unit test, so `isVisible` fails closed and every
      // signed-in-only destination is unreachable. That is the same path a
      // guest following a stale /cgpa link takes: land on the default screen,
      // not on an empty one.
      expect(AppRoutes.screenIn(Uri.parse('/cgpa')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/admin')), isNull);
    });

    test('ignores the root, unknown slugs and deeper paths', () {
      expect(AppRoutes.screenIn(Uri.parse('/')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/not-a-screen')), isNull);
      expect(AppRoutes.screenIn(Uri.parse('/minors/cs')), isNull);
    });

    test('round-trips every destination through its own path', () {
      for (final destination in AppDestinations.all) {
        final uri = Uri.parse(AppRoutes.pathFor(destination.screen));
        expect(uri.pathSegments, [destination.slug]);
      }
    });

    test('slugs are unique and URL-safe', () {
      final slugs = AppDestinations.all.map((d) => d.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
      for (final slug in slugs) {
        expect(slug, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')), reason: slug);
      }
    });
  });

  group('AppRoutes.currentUri', () {
    // What the Router reads to decide what the address bar should say, and
    // whether the move deserves a history entry.
    final history = AppRoutes.history;
    final shell = _FakeRoute(const RouteSettings(name: '/'), isFirst: true);

    setUp(() => history.didPush(shell, null));
    tearDown(() => history.didPop(shell, null));

    Route<dynamic> route(String? name) =>
        _FakeRoute(RouteSettings(name: name), isFirst: false);

    test('names the pushed screen the user is looking at', () {
      final credits = route('/credits');
      history.didPush(credits, shell);
      expect(AppRoutes.currentUri.path, '/credits');
      history.didPop(credits, shell);
    });

    test('a dialog over a screen does not change the URL', () {
      // The trap in reporting only the topmost route: a menu, sheet or dialog
      // is pushed without settings, and answering `/` for it would rewrite the
      // address bar the moment the user opened one.
      final credits = route('/credits');
      final dialog = route(null);
      history.didPush(credits, shell);
      history.didPush(dialog, credits);

      expect(AppRoutes.currentUri.path, '/credits');
      // …while Back still belongs to the dialog, which may refuse to close.
      expect(history.isShowingPage, isFalse);

      history.didPop(dialog, credits);
      history.didPop(credits, shell);
    });

    test('stops naming a screen once it closes', () {
      final credits = route('/credits');
      history.didPush(credits, shell);
      history.didPop(credits, shell);
      // No shell mounted in a unit test, and not web, so this is the root.
      expect(AppRoutes.currentUri.path, '/');
    });

    test('a screen replaced by another names the newcomer', () {
      final credits = route('/credits');
      final profile = route('/profile');
      history.didPush(credits, shell);
      history.didReplace(newRoute: profile, oldRoute: credits);
      expect(AppRoutes.currentUri.path, '/profile');
      history.didRemove(profile, shell);
      expect(AppRoutes.currentUri.path, '/');
    });
  });

  group('AppRoutes pushed-screen routes', () {
    // No Firebase in a unit test, so `isSignedIn()` fails closed and every
    // signedInOnly screen is unreachable — the same path a signed-out visitor
    // following a stale link takes.
    test('a signed-out visitor cannot reach a signed-in-only screen', () {
      expect(AppTools.of(AppTool.profile).signedInOnly, isTrue);
      expect(AppRoutes.pageIn(Uri.parse('/profile')), isNull);
      expect(
        AppRoutes.onGenerateRoute(const RouteSettings(name: '/profile')),
        isNull,
        reason: 'an ungenerated initial route is what makes Flutter fall back '
            'to the app instead of showing an empty profile form',
      );
      // The tools reached from the timetable list are gated the same way.
      for (final tool in [AppTool.electives, AppTool.prerequisites]) {
        expect(AppRoutes.pathForTool(tool), isNotNull, reason: tool.name);
        expect(AppRoutes.pageIn(Uri.parse(AppRoutes.pathForTool(tool)!)), isNull,
            reason: tool.name);
      }
    });

    test('resolves a public screen by path', () {
      expect(AppRoutes.pageIn(Uri.parse('/credits'))?.tool, AppTool.credits);
      expect(AppRoutes.pageIn(Uri.parse('/credits/extra')), isNull);
      expect(AppRoutes.pageIn(Uri.parse('/')), isNull);
    });

    test('builds the expected absolute paths', () {
      expect(AppRoutes.pathForTool(AppTool.profile), '/profile');
      expect(AppRoutes.pathForTool(AppTool.electives), '/electives');
      expect(AppRoutes.pathForTool(AppTool.prerequisites), '/prerequisites');
      expect(AppRoutes.pathForTool(AppTool.courseGuide), '/course-guide');
    });

    test('a tool that is already a shell tab gets no second URL', () {
      // Minors and Prof Chambers are destinations too. Two URLs for one screen
      // splits its own search ranking and makes "which link do I send?" a
      // question nobody should have to answer.
      for (final tool in [AppTool.minors, AppTool.profChambers]) {
        final info = AppTools.of(tool);
        expect(info.screen, isNotNull, reason: tool.name);
        expect(info.segment, isNull, reason: tool.name);
      }
    });

    test('creates a named route for a reachable screen, and nothing else', () {
      expect(AppRoutes.onGenerateRoute(const RouteSettings(name: '/credits')),
          isNotNull);
      expect(AppRoutes.onGenerateRoute(const RouteSettings(name: '/missing')),
          isNull);
      expect(AppRoutes.onGenerateRoute(const RouteSettings(name: null)), isNull);
    });

    test('the generated route keeps its name, so Back can identify it', () {
      // AppRoutes.applyUrl tells "a registered screen is open" from "the editor
      // is open" by this name alone, and pops the second one only through its
      // guard.
      final route =
          AppRoutes.onGenerateRoute(const RouteSettings(name: '/credits'));
      expect(route!.settings.name, '/credits');
      expect(AppRoutes.history.isShowingPage, isFalse);
    });

    test('segments never collide with a tab slug or each other', () {
      // Two registries, one URL space: a destination slugged `electives` would
      // silently shadow the pushed screen, or the other way round, and only
      // ever show up as a link that opens the wrong thing.
      final slugs = AppDestinations.all.map((d) => d.slug).toSet();
      final segments = [
        for (final info in AppTools.all)
          if (info.segment != null) info.segment!,
      ];
      expect(segments.toSet(), hasLength(segments.length));
      for (final segment in segments) {
        expect(slugs, isNot(contains(segment)), reason: segment);
        expect(segment, isNot(AppRoutes.shareSegment));
        expect(segment, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
      }
    });
  });

  group('AppRoutes.launchPageToOpen', () {
    test('opens the screen a launch URL names', () {
      expect(AppRoutes.launchPageToOpen(Uri.parse('/credits'), '/'), '/credits');
    });

    test('does not re-open one Flutter already stacked', () {
      // A public screen is generated from the browser path before the shell
      // exists. Pushing it again put two copies on the stack and the user had
      // to close it twice.
      expect(AppRoutes.launchPageToOpen(Uri.parse('/credits'), '/credits'), isNull);
    });

    test('ignores tabs and unknown paths', () {
      expect(AppRoutes.launchPageToOpen(Uri.parse('/timetables'), '/'), isNull);
      expect(AppRoutes.launchPageToOpen(Uri.parse('/nope'), '/'), isNull);
      expect(AppRoutes.launchPageToOpen(Uri.parse('/'), '/'), isNull);
    });

    test('still respects the gate', () {
      // Signed out here, as during MaterialApp's first build — which is the
      // whole reason the shell asks again once auth has resolved.
      expect(AppRoutes.launchPageToOpen(Uri.parse('/prerequisites'), '/'), isNull);
      expect(AppRoutes.launchPageToOpen(Uri.parse('/profile'), '/'), isNull);
    });
  });

  group('AppRouteHistory', () {
    test('the editor, menus and dialogs own no address', () {
      // Pushed anonymously and deliberately unaddressable: a URL that could
      // push or pop the editor would be a way around its unsaved-changes guard.
      expect(AppRouteHistory.isAddressable(null), isFalse);
      expect(AppRouteHistory.isAddressable('/not-a-screen'), isFalse);
    });

    test('an addressable path stays addressable when its gate closes', () {
      // isAddressable answers "did this route own an address", not "may this
      // user open it" — a signed-out session must still recognise /profile on
      // the way out, or the URL is never corrected.
      expect(AppRouteHistory.isAddressable('/profile'), isTrue);
      expect(AppRoutes.pageIn(Uri.parse('/profile')), isNull);
    });
  });

  group('AppRoutes share links', () {
    test('reads the code out of a /s/<code> url', () {
      expect(AppRoutes.shareCodeIn(Uri.parse('https://tabulr.net/s/abc-123')),
          'abc-123');
    });

    test('is not fooled by other two-segment paths', () {
      expect(AppRoutes.shareCodeIn(Uri.parse('/courses/cs-f211')), isNull);
      expect(AppRoutes.shareCodeIn(Uri.parse('/s')), isNull);
      expect(AppRoutes.shareCodeIn(Uri.parse('/s/')), isNull);
    });

    test('accepts a pasted link or a bare code', () {
      const code = '5f2c9b1a-0000-4000-8000-abcdefabcdef';
      expect(AppRoutes.shareCodeInText('  https://tabulr.net/s/$code '), code);
      expect(AppRoutes.shareCodeInText(' $code '), code);
      expect(AppRoutes.shareCodeInText('   '), isNull);
    });
  });

  // A launch path this app generates no route for must leave the user on the
  // shell rather than on nothing. Covers a signed-out `/profile` and every tab
  // URL (`/cgpa`) alike, since tabs are not routes at all.
  testWidgets('an unopenable launch path lands on the shell', (tester) async {
    await tester.pumpWidget(MaterialApp.router(
      routeInformationParser: const AppRouteInformationParser(),
      routerDelegate: AppRouterDelegate(home: const Text('shell')),
      routeInformationProvider: PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: Uri.parse('/profile')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('shell'), findsOneWidget);
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
  });
}

/// Minimal stand-in: the history stack reads only `settings.name`.
class _FakeRoute extends Route<dynamic> {
  _FakeRoute(this._settings, {required this.isFirst});

  final RouteSettings _settings;

  @override
  final bool isFirst;

  @override
  RouteSettings get settings => _settings;
}
