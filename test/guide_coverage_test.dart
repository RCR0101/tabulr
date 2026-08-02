import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/guide_content.dart';
import 'package:timetable_maker/utils/page_info_helper.dart';
import 'package:timetable_maker/widgets/app_destinations.dart';
import 'package:timetable_maker/widgets/app_tools.dart';
import 'package:timetable_maker/widgets/command_palette.dart';

void main() {
  final anchors = {for (final topic in guideTopics) topic.anchor};

  test('every documented screen points at a topic that exists', () {
    for (final screen in DrawerScreen.values) {
      final anchor = guideAnchorForScreen(screen);
      if (anchor == null) continue;
      expect(anchors, contains(anchor), reason: '$screen → "$anchor"');
    }
  });

  test('every documented tool points at a topic that exists', () {
    for (final tool in AppTool.values) {
      final anchor = guideAnchorForTool(tool);
      if (anchor == null) continue;
      expect(anchors, contains(anchor), reason: '$tool → "$anchor"');
    }
  });

  test('only the admin suite is left undocumented', () {
    final undocumented = [
      for (final screen in DrawerScreen.values)
        if (guideAnchorForScreen(screen) == null) screen,
    ];
    expect(undocumented, [DrawerScreen.admin]);
    expect(
      [for (final t in AppTool.values) if (guideAnchorForTool(t) == null) t],
      isEmpty,
    );
  });

  test('anchors are unique and URL-safe', () {
    final seen = <String>{};
    for (final topic in guideTopics) {
      expect(seen.add(topic.anchor), isTrue,
          reason: 'duplicate anchor "${topic.anchor}"');
      expect(topic.anchor, matches(RegExp(r'^[a-z0-9-]+$')),
          reason: topic.anchor);
    }
    for (final section in guideSections) {
      expect(section.anchor, matches(RegExp(r'^[a-z0-9-]+$')));
    }
  });

  test('every in-app page info is reused by a topic', () {
    final used = {
      for (final topic in guideTopics)
        if (topic.pageInfo != null) topic.pageInfo!.title,
    };
    for (final info in PageInfoHelper.all) {
      expect(used, contains(info.title), reason: info.title);
    }
  });

  test('page info entries are distinct and complete', () {
    expect(PageInfoHelper.all.map((i) => i.title).toSet(),
        hasLength(PageInfoHelper.all.length));
    for (final info in PageInfoHelper.all) {
      expect(info.purpose.length, greaterThan(40), reason: info.title);
      expect(info.features, isNotEmpty, reason: info.title);
    }
  });

  test('search finds a topic by keyword, title and feature text', () {
    bool findable(String query) => guideTopics.any((t) => t.matches(query));

    expect(findable('share code'), isTrue);
    expect(findable('exam clash'), isTrue);
    expect(findable('amoled'), isTrue);
    expect(findable('performance sheet'), isTrue);
    expect(findable('zzzz'), isFalse);
  });

  test('every topic has substance', () {
    for (final topic in guideTopics) {
      expect(topic.title, isNotEmpty);
      expect(topic.lead.length, greaterThan(60), reason: topic.anchor);
      expect(topic.keywords, isNotEmpty, reason: topic.anchor);
    }
  });

  test('the command palette can reach every guide topic', () {
    expect(CommandCategory.values, contains(CommandCategory.guide));
    for (final topic in guideTopics) {
      expect(topic.title.trim(), isNotEmpty);
      expect(topic.lead.contains('. '), isTrue,
          reason: '${topic.anchor} lead has no sentence break to use as a subtitle');
    }
  });
}
