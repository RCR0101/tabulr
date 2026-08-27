import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/guide_screen.dart';
import 'package:timetable_maker/utils/page_info_helper.dart';
import 'package:timetable_maker/utils/guide_content.dart';

void main() {
  testWidgets('page info opens its registered topic', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  PageInfoHelper.show(context, PageInfoHelper.degreeAudit),
              child: const Text('Info'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read the guide'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GuideScreen>(find.byType(GuideScreen)).initialAnchor,
      'degree-audit',
    );
    expect(tester.takeException(), isNull);
  });

  test('corrected help covers limitations and current workflows', () {
    expect(
      guideTopicAt('swapping-sections')!.lead,
      contains('two other courses'),
    );
    expect(guideTopicAt('cg-booster')!.lead, contains('retake combinations'));
    expect(
      guideTopicAt('free-slots')!.lead,
      contains('does not send an invitation'),
    );
    expect(
      guideTopicAt('acad-drives')!.lead,
      contains('no direct file-upload'),
    );
    expect(guideTopicAt('degree-audit')!.lead, contains('not certified'));
    expect(guideTopicAt('finding-your-way')!.lead, contains('Help & support'));
    expect(
      guideTopicAt('sample-timetables')!.lead,
      contains('directly on the page'),
    );
    expect(
      guideTopicAt('sample-timetables')!.steps,
      contains(contains('Use this sample')),
    );
    expect(guideTopicAt('exam-seating')!.lead, contains('published ID range'));
    expect(
      guideTopicAt('exam-seating')!.steps,
      contains(contains('Find rooms')),
    );
    for (final info in PageInfoHelper.all) {
      expect(
        guideTopics.where((t) => identical(t.pageInfo, info)),
        hasLength(1),
        reason: '${info.title} must have one canonical help topic',
      );
    }
  });
}
