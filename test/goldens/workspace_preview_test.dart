import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/guide_screen.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:timetable_maker/widgets/app_workspaces.dart';
import 'package:timetable_maker/widgets/workspace_frame.dart';
import '../helpers/preview_harness.dart';

void main() {
  setUpAll(loadPreviewFont);
  for (final width in [2880.0, 780.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'workspace ${width == 2880 ? 'desktop' : 'phone'} ${dark ? 'dark' : 'light'}',
        (tester) async {
          usePreviewSurface(tester, Size(width, width == 2880 ? 1800 : 1688));
          final help = AppWorkspaces.of(AppWorkspace.help);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark
                  ? ThemeService().getDarkThemeData(AppTheme.githubDark)
                  : ThemeService().getLightThemeData(AppTheme.githubDark),
              home: WorkspaceFrame(
                workspace: help,
                workspaces: AppWorkspaces.all,
                entries: help.entries,
                selectedId: 'guide',
                onWorkspaceSelected: (_) {},
                onEntrySelected: (_) {},
                onSearch: () {},
                onTheme: () {},
                onProfile: () {},
                collapsed: false,
                onToggleCollapse: () {},
                child: const GuideScreen(embedded: true),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            'workspace_${width == 2880 ? 'desktop' : 'phone'}_${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }
}
