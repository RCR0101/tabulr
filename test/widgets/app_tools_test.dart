import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_selection_link.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';
import 'package:timetable_maker/widgets/app_tools.dart';

TimetableSelectionLink link() => TimetableSelectionLink(
      selectedSections: <SelectedSection>[],
      availableCourses: const [],
      revision: ValueNotifier(0),
      timetableName: 'Sem 1',
      onSectionToggle: (_, __, ___) {},
    );

void main() {
  group('AppTools', () {
    test('describes every tool', () {
      expect(AppTools.all.length, AppTool.values.length);
      for (final tool in AppTool.values) {
        expect(AppTools.of(tool).tool, tool);
      }
    });

    test('every tool is labelled and described', () {
      for (final info in AppTools.all) {
        expect(info.label, isNotEmpty, reason: '${info.tool}');
        expect(info.description, isNotEmpty, reason: '${info.tool}');
      }
    });

    test('labels are unique', () {
      final labels = AppTools.all.map((i) => i.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('the editor menu holds the course-planning tools', () {
      expect(
        AppTools.editorMenu.map((i) => i.tool),
        [
          AppTool.courseGuide,
          AppTool.prerequisites,
          AppTool.disciplineElectives,
          AppTool.humanitiesElectives,
          AppTool.openElectives,
          AppTool.minors,
          AppTool.profChambers,
        ],
      );
    });

    test('Compare and Credits stay out of the editor menu', () {
      expect(AppTools.of(AppTool.compareTimetables).inEditorMenu, isFalse);
      expect(AppTools.of(AppTool.credits).inEditorMenu, isFalse);
    });

    test('byName round-trips, and rejects anything else', () {
      for (final tool in AppTool.values) {
        expect(AppTools.byName(tool.name), tool);
      }
      // The mobile overflow menu shares its value space with other actions.
      expect(AppTools.byName('export_png'), isNull);
      expect(AppTools.byName(''), isNull);
    });

    test('only the tools that are also shell screens carry one', () {
      final withScreen = {
        for (final info in AppTools.all)
          if (info.screen != null) info.tool: info.screen,
      };
      expect(withScreen, {
        AppTool.minors: DrawerScreen.minors,
        AppTool.profChambers: DrawerScreen.profChambers,
      });
    });

    test('builds every tool with and without a link', () {
      // The link is null outside the editor; no tool may require it.
      for (final info in AppTools.all) {
        expect(info.build(null), isNotNull, reason: '${info.tool}');
        expect(info.build(link()), isNotNull, reason: '${info.tool}');
      }
    });
  });
}
