import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/guide_screen.dart';
import 'package:timetable_maker/utils/admin_guide_content.dart';
import 'package:timetable_maker/utils/guide_content.dart';

void main() {
  final topics = [for (final s in adminGuideSections) ...s.topics];
  final text = topics.map((t) => '${t.title}\n${t.lead}\n${t.steps.join('\n')}').join('\n');

  test('every admin dashboard card and section is in the handbook', () {
    // Read from the dashboard source, so a new card without a handbook entry
    // fails here rather than going undocumented.
    final src = File('lib/screens/admin_screen.dart').readAsStringSync();
    final titles = {
      for (final m in RegExp(r"_managementCard\([^)]*?title: '([^']+)'", dotAll: true).allMatches(src))
        m.group(1)!,
      for (final m in RegExp(r"_buildSection\(\s*(?:key:[^\n]*\n\s*)?title: '([^']+)'").allMatches(src))
        m.group(1)!,
    };
    expect(titles.length, greaterThan(15), reason: 'the source pattern stopped matching');
    for (final title in titles) {
      final bare = title.replaceAll(RegExp(r'\s*\(.*\)'), '');
      expect(text, contains(bare), reason: '"$title" is on the dashboard but not in the handbook');
    }
  });

  test('anchors are unique, URL-safe and distinct from the student guide', () {
    final student = {for (final t in guideTopics) t.anchor};
    final seen = <String>{};
    for (final t in topics) {
      expect(seen.add(t.anchor), isTrue, reason: 'duplicate ${t.anchor}');
      expect(t.anchor, matches(RegExp(r'^[a-z0-9-]+$')));
      expect(student, isNot(contains(t.anchor)));
      expect(t.steps, isNotEmpty, reason: t.title);
    }
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('renders at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: GuideScreen(sections: adminGuideSections, title: 'Admin handbook', linkable: false),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Admin handbook'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsNothing);
    });
  }
}
