import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_stats.dart';
import 'package:timetable_maker/services/ui/theme_service.dart';
import 'package:timetable_maker/utils/design_constants.dart';
import 'package:timetable_maker/widgets/app_workspaces.dart';
import 'package:timetable_maker/widgets/timetables/timetable_library_card.dart';
import 'package:timetable_maker/widgets/workspace_navigation_scope.dart';

import '../helpers/preview_harness.dart';
import '../helpers/test_data.dart';

/// The surfaces the user called "boxy": the timetable library card and the
/// workspace tab strip. Writes PNGs; asserts nothing.
void main() {
  setUpAll(loadPreviewFont);

  final courses = [
    makeCourse(
      courseCode: 'CS F211',
      sections: [
        makeSection(days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F], hours: [1]),
      ],
    ),
    makeCourse(
      courseCode: 'MATH F211',
      sections: [
        makeSection(days: [DayOfWeek.T, DayOfWeek.Th], hours: [2, 3]),
      ],
    ),
    makeCourse(
      courseCode: 'EEE F111',
      sections: [
        makeSection(days: [DayOfWeek.W, DayOfWeek.S], hours: [5, 6]),
      ],
    ),
  ];
  final timetable = makeTimetable(courses: courses, name: 'Sem 1 — plan A');

  for (final width in [1240.0, 820.0]) {
    for (final (label, brightness) in previewBrightnesses) {
      final name =
          'rounded_${width == 1240 ? 'desktop' : 'phone'}_$label';
      testWidgets(name, (tester) async {
        usePreviewSurface(tester, Size(width * 2, 1500));
        final theme =
            brightness == Brightness.dark
                ? ThemeService().getDarkThemeData(AppTheme.githubDark)
                : ThemeService().getLightThemeData(AppTheme.githubDark);
        final degree = AppWorkspaces.of(AppWorkspace.degree);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              body: Builder(
                builder: (context) => ListView(
                children: [
                  WorkspaceTabs(
                    entries: degree.entries,
                    selectedId: degree.entries[2].id,
                    onSelected: (_) {},
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < 2; i++)
                    TimetableLibraryCard(
                      timetable: timetable,
                      stats: TimetableStats.fromTimetable(timetable),
                      courseCodes: const [
                        'CS F211',
                        'MATH F211',
                        'EEE F111',
                      ],
                      totalCredits: 12,
                      creditBasis: CreditBasis.units,
                      accent: AppDesign.timetableColors(
                        context,
                      )[i],
                      index: i,
                      isCustomSort: i == 0,
                      canDelete: true,
                      updatedLabel: '2 days ago',
                      onOpen: (_) {},
                      onInsights: () {},
                      onRename: () {},
                      onDuplicate: () {},
                      onDelete: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(tester, name);
      });
    }
  }
}
