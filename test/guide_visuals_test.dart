import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/guide_content.dart';
import 'package:timetable_maker/widgets/guide_visuals.dart';

void main() {
  for (final visual in GuideVisual.values) {
    for (final (label, width) in const [('phone', 380.0), ('desktop', 820.0)]) {
      testWidgets('$visual renders at $label width', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuideVisualFrame(visual: visual),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(GuideVisualFrame), findsOneWidget);
      });
    }
  }
}
