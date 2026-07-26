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
      // AppRouteObserver tells "a registered screen is open" from "the editor
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

  group('AppRouteHistory url restore', () {
    Route<dynamic> route(String? name, {bool isFirst = false}) =>
        _FakeRoute(RouteSettings(name: name), isFirst: isFirst);

    final shell = route('/', isFirst: true);

    test('restores the tab URL when an addressable screen closes', () {
      // /credits announced itself on the way in, and the Navigator announces
      // the shell's own `/` on the way out. Without the correction the address
      // bar reads `/` while some other tab is showing.
      expect(AppRouteHistory.needsUrlRestore(route('/credits'), shell), isTrue);
    });

    test('does not restore for a menu, dialog or sheet', () {
      // The regression: picking an item from the Tools PopupMenuButton pops the
      // menu route *before* running onSelected, so a correction scheduled here
      // landed after the pushed screen and put the URL back on /timetables.
      expect(AppRouteHistory.needsUrlRestore(route(null), shell), isFalse);
    });

    test('does not restore for the timetable editor', () {
      // Pushed anonymously and deliberately unaddressable, so it never wrote a
      // URL there is anything to restore.
      expect(AppRouteHistory.needsUrlRestore(route(null), shell), isFalse);
      expect(AppRouteHistory.isAddressable(null), isFalse);
      expect(AppRouteHistory.isAddressable('/not-a-screen'), isFalse);
    });

    test('does not restore when another pushed screen is uncovered', () {
      // The Navigator announces the uncovered route's own name, which is right.
      expect(
        AppRouteHistory.needsUrlRestore(route('/profile'), route('/credits')),
        isFalse,
      );
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

  // The reason AppShell must NOT push the launch URL's page itself. Uses a stub
  // route table rather than the real one because the claim under test is
  // Flutter's, not ours: a MaterialApp generates the initial route from the
  // launch path, so anything that also pushes it stacks the page twice and the
  // user has to close it twice.
  testWidgets('Flutter pushes the launch URL page without any help', (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/credits',
      onGenerateRoute: (settings) => settings.name == '/credits'
          ? MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Text('page'),
            )
          : null,
      home: const Text('shell'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('page'), findsOneWidget);
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isTrue,
        reason: 'the page is stacked over the shell, not replacing it');
  });

  // The other half: a launch path this app does not generate a route for must
  // leave the user on the shell. That covers both a signed-out `/profile` and
  // every tab URL (`/cgpa`), since tabs are not routes at all.
  testWidgets('an ungenerated launch route falls back to the shell', (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/profile',
      onGenerateRoute: AppRoutes.onGenerateRoute, // signed out -> null
      home: const Text('shell'),
    ));
    await tester.pumpAndSettle();

    // Flutter reports "Could not navigate to initial route" and falls back to
    // `/`. The report is debug-only (it sits inside an assert), so it is
    // console noise for a developer deep-linking locally and absent from
    // release builds — the fallback itself is the behaviour we want.
    expect(tester.takeException(), contains('Could not navigate to initial route'));
    expect(find.text('shell'), findsOneWidget);
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
  });
}

/// Minimal stand-in: [needsUrlRestore] reads only `settings.name` and `isFirst`.
class _FakeRoute extends Route<dynamic> {
  _FakeRoute(this._settings, {required this.isFirst});

  final RouteSettings _settings;

  @override
  final bool isFirst;

  @override
  RouteSettings get settings => _settings;
}
