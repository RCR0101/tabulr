import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/guide_screen.dart';
import 'package:timetable_maker/utils/guide_content.dart';

void main() {
  Future<void> pumpGuide(WidgetTester tester, double width,
      {String? anchor}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: GuideScreen(initialAnchor: anchor),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders on a phone', (tester) async {
    await pumpGuide(tester, 390);
    expect(tester.takeException(), isNull);
    expect(find.text(guideSections.first.title), findsWidgets);
  });

  testWidgets('renders with the rail on a wide screen', (tester) async {
    await pumpGuide(tester, 1200);
    expect(tester.takeException(), isNull);
    expect(find.text(guideTopics.first.title), findsNWidgets(2));
  });

  testWidgets('search narrows to matching topics', (tester) async {
    await pumpGuide(tester, 1200);
    await tester.enterText(find.byType(TextField).first, 'amoled');
    await tester.pumpAndSettle();
    expect(find.text('1 topic for "amoled"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search with no match offers a way out', (tester) async {
    await pumpGuide(tester, 1200);
    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Clear search'), findsOneWidget);
  });

  testWidgets('opens scrolled to a deep anchor', (tester) async {
    const anchor = 'acad-drives';
    final topic = guideTopicAt(anchor)!;
    await pumpGuide(tester, 1200, anchor: anchor);

    expect(tester.takeException(), isNull);
    expect(find.text(topic.lead), findsOneWidget);
  });

  testWidgets('the rail scrolls the body to a far-off topic', (tester) async {
    await pumpGuide(tester, 1200);
    final topic = guideTopicAt('cgpa')!;
    final lead = find.text(topic.lead);
    expect(lead, findsOneWidget);
    expect(tester.getTopLeft(lead).dy, greaterThan(1400));

    await tester.tap(find.text(topic.title).first);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(lead).dy, lessThan(400));
    expect(tester.takeException(), isNull);
  });
}
