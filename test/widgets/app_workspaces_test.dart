import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';
import 'package:timetable_maker/widgets/app_tools.dart';
import 'package:timetable_maker/widgets/app_workspaces.dart';
import 'package:timetable_maker/widgets/workspace_frame.dart';
import 'package:timetable_maker/widgets/workspace_navigation_scope.dart';
import 'package:timetable_maker/utils/design_constants.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:timetable_maker/services/ui/responsive_service.dart';

void main() {
  test('Degree Audit remains the final Degree destination', () {
    expect(
      AppWorkspaces.of(AppWorkspace.degree).entries.last.tool,
      AppTool.degreeAudit,
    );
  });

  test('search context includes the visible workspace and section labels', () {
    expect(
      AppWorkspaces.contextForScreen(DrawerScreen.cgpaCalculator),
      'Degree / Grades & targets',
    );
    expect(
      AppWorkspaces.contextForScreen(DrawerScreen.freeSlotFinder),
      'Calendar / Availability',
    );
    expect(
      AppWorkspaces.contextForTool(AppTool.guide),
      'Help & support / Using Tabulr',
    );
    expect(AppWorkspaces.contextForTool(AppTool.trimTimetable), isNull);
  });

  test('each shell destination belongs to exactly one workspace', () {
    final entries = AppWorkspaces.all.expand((w) => w.entries).toList();
    for (final screen in DrawerScreen.values) {
      expect(entries.where((e) => e.screen == screen), hasLength(1));
    }
    expect(entries.map((e) => e.id).toSet(), hasLength(entries.length));
    expect(AppWorkspaces.primary, hasLength(5));
  });

  test('guests retain public features without inheriting private access', () {
    expect(
      AppWorkspaces.of(AppWorkspace.degree).visibleEntries.map((e) => e.id),
      ['minors'],
    );
    expect(
      AppWorkspaces.of(AppWorkspace.explore).visibleEntries.map((e) => e.id),
      ['courseHistory'],
    );
    expect(
      AppWorkspaces.of(AppWorkspace.help).visibleEntries.map((e) => e.id),
      ['guide', 'faq', 'credits'],
    );
    expect(AppWorkspaces.of(AppWorkspace.calendar).visibleEntries, isEmpty);
    expect(AppWorkspaces.of(AppWorkspace.admin).visibleEntries, isEmpty);
  });

  test('contextual tools and global utilities are not workspace pages', () {
    for (final tool in [
      AppTool.trimTimetable,
      AppTool.compareTimetables,
      AppTool.profile,
    ]) {
      expect(AppWorkspaces.forTool(tool), isNull);
    }
    expect(
      AppWorkspaces.forTool(AppTool.minors)?.workspace,
      AppWorkspace.degree,
    );
    expect(
      AppWorkspaces.forTool(AppTool.profChambers)?.workspace,
      AppWorkspace.explore,
    );
    expect(AppWorkspaces.forTool(AppTool.guide)?.workspace, AppWorkspace.help);
  });

  for (final size in [
    const Size(1440, 900),
    const Size(1200, 440),
    const Size(820, 900),
    const Size(390, 844),
    const Size(320, 640),
    const Size(844, 390),
  ]) {
    testWidgets('workspace chrome is usable at ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final workspace = AppWorkspaces.of(AppWorkspace.degree);
      WorkspaceEntry? selected;
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().getLightThemeData(AppTheme.githubDark),
          home: WorkspaceFrame(
            workspace: workspace,
            workspaces: AppWorkspaces.all,
            entries: workspace.entries,
            selectedId: 'degreeAudit',
            onWorkspaceSelected: (_) {},
            onEntrySelected: (e) => selected = e,
            onSearch: () => searches++,
            onTheme: () {},
            onProfile: () {},
            collapsed: false,
            onToggleCollapse: () {},
            child: Builder(
              builder:
                  (context) => Scaffold(
                    appBar: AppDesign.appBar(context, title: 'Feature page'),
                    body: const SizedBox.expand(
                      key: ValueKey('feature-body'),
                      child: Text('Feature body'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Grades & targets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grades & targets'));
      expect(selected?.screen, DrawerScreen.cgpaCalculator);
      await tester.tap(find.byTooltip('Search anything').last);
      expect(searches, 1);
      final mobile = ResponsiveService.isMobile(
        tester.element(find.byType(WorkspaceFrame)),
      );
      if (mobile) {
        final bodyHeight =
            tester.getSize(find.byKey(const ValueKey('feature-body'))).height;
        expect(bodyHeight, greaterThanOrEqualTo(size.height - 180));
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('More'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Help & support'),
          160,
          scrollable:
              find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
        expect(find.text('Help & support'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } else {
        expect(
          find.byTooltip('Help & support'),
          size.width <= 1024 ? findsOneWidget : findsNothing,
        );
      }
    });
  }

  testWidgets('single-entry mobile workspaces do not reserve tab space', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final workspace = AppWorkspaces.of(AppWorkspace.exams);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceFrame(
          workspace: workspace,
          workspaces: AppWorkspaces.all,
          entries: workspace.entries,
          selectedId: 'examSeating',
          onWorkspaceSelected: (_) {},
          onEntrySelected: (_) {},
          onSearch: () {},
          onTheme: () {},
          onProfile: null,
          collapsed: false,
          onToggleCollapse: () {},
          child: Builder(
            builder:
                (context) => Scaffold(
                  appBar: AppDesign.appBar(context, title: 'Exam seating'),
                  body: const SizedBox.expand(
                    key: ValueKey('single-entry-body'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceTabs), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('single-entry-body'))).height,
      greaterThanOrEqualTo(500),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long tabs reveal the selected destination and support large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final entries = AppWorkspaces.of(AppWorkspace.degree).entries;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: WorkspaceTabs(
                entries: entries,
                selectedId: 'minors',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Minors').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mobile workspace tabs follow scroll direction smoothly', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final workspace = AppWorkspaces.of(AppWorkspace.degree);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceFrame(
          workspace: workspace,
          workspaces: AppWorkspaces.all,
          entries: workspace.entries,
          selectedId: 'minors',
          onWorkspaceSelected: (_) {},
          onEntrySelected: (_) {},
          onSearch: () {},
          onTheme: () {},
          onProfile: null,
          collapsed: false,
          onToggleCollapse: () {},
          child: Builder(
            builder:
                (context) => Scaffold(
                  appBar: AppDesign.appBar(
                    context,
                    title: 'Scrollable feature',
                  ),
                  body: ListView.builder(
                    key: const ValueKey('feature-list'),
                    itemExtent: 56,
                    itemCount: 40,
                    itemBuilder: (_, index) => Text('Item $index'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expandedHeight = tester.getSize(find.byType(AppBar)).height;
    expect(expandedHeight, greaterThan(90));

    await tester.drag(
      find.byKey(const ValueKey('feature-list')),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final transitionHeight = tester.getSize(find.byType(AppBar)).height;
    expect(
      tester
          .widget<WorkspaceNavigationScope>(
            find.byType(WorkspaceNavigationScope),
          )
          .tabVisibility,
      lessThan(1),
    );
    expect(transitionHeight, lessThan(expandedHeight));
    expect(transitionHeight, greaterThan(56));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, closeTo(56, 0.1));

    await tester.drag(
      find.byKey(const ValueKey('feature-list')),
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AppBar)).height,
      closeTo(expandedHeight, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile workspace tabs yield their space to the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final workspace = AppWorkspaces.of(AppWorkspace.degree);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceFrame(
          workspace: workspace,
          workspaces: AppWorkspaces.all,
          entries: workspace.entries,
          selectedId: 'minors',
          onWorkspaceSelected: (_) {},
          onEntrySelected: (_) {},
          onSearch: () {},
          onTheme: () {},
          onProfile: null,
          collapsed: false,
          onToggleCollapse: () {},
          child: Builder(
            builder:
                (context) => Scaffold(
                  appBar: AppDesign.appBar(context, title: 'Search feature'),
                  body: const TextField(key: ValueKey('search-field')),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, greaterThan(90));

    await tester.showKeyboard(find.byKey(const ValueKey('search-field')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, closeTo(56, 0.1));
    expect(tester.takeException(), isNull);
  });
}
