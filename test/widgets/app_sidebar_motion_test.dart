import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/tutorial_service.dart';
import 'package:timetable_maker/widgets/app_workspaces.dart';
import 'package:timetable_maker/widgets/workspace_frame.dart';

void main() {
  testWidgets(
    'desktop sidebar animates between expanded and collapsed widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      var collapsed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              final workspace = AppWorkspaces.of(AppWorkspace.calendar);
              return WorkspaceFrame(
                workspace: workspace,
                workspaces: AppWorkspaces.all,
                entries: workspace.entries,
                selectedId: workspace.entries.first.id,
                onWorkspaceSelected: (_) {},
                onEntrySelected: (_) {},
                onSearch: () {},
                onTheme: () {},
                onProfile: () {},
                collapsed: collapsed,
                onToggleCollapse: () => setState(() => collapsed = !collapsed),
                child: const SizedBox(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sidebar = find.byKey(TutorialKeys.sidebarNav);
      expect(tester.getSize(sidebar).width, 232);
      await tester.tap(find.text('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final midpoint = tester.getSize(sidebar).width;
      expect(midpoint, greaterThan(76));
      expect(midpoint, lessThan(232));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 76);
      expect(tester.takeException(), isNull);
    },
  );
}
