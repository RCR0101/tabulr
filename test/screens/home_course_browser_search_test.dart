import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/widgets/search_filter_widget.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('course browser search reports queries at ${size.width}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final queries = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchFilterWidget(
              onSearchChanged: (query, _) => queries.add(query),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'biology');
      await tester.pump(const Duration(milliseconds: 249));
      expect(queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(queries, ['biology']);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(queries.last, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
