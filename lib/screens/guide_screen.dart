import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_routes.dart';
import '../utils/design_constants.dart';
import '../utils/guide_content.dart';
import '../utils/page_info_helper.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/app_tools.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/guide_visuals.dart';

class GuideScreen extends StatefulWidget {
  final String? initialAnchor;

  const GuideScreen({super.key, this.initialAnchor});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const double _railBreakpoint = 900;

  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {
    for (final topic in guideTopics) topic.anchor: GlobalKey(),
  };

  String _query = '';

  bool _showVisuals = false;

  final ValueNotifier<String?> _current =
      ValueNotifier(guideSections.first.topics.first.anchor);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncCurrent);
    final fragment = Uri.base.fragment;
    final anchor = widget.initialAnchor ?? (fragment.isEmpty ? null : fragment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showVisuals = true);
      if (anchor != null && _keys.containsKey(anchor)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(anchor));
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncCurrent);
    _scroll.dispose();
    _search.dispose();
    _current.dispose();
    super.dispose();
  }

  List<GuideSection> get _visible {
    if (_query.isEmpty) return guideSections;
    return [
      for (final section in guideSections)
        if (section.topics.any((t) => t.matches(_query)))
          GuideSection(
            title: section.title,
            anchor: section.anchor,
            icon: section.icon,
            blurb: section.blurb,
            topics: section.topics.where((t) => t.matches(_query)).toList(),
          ),
    ];
  }

  int get _resultCount =>
      _visible.fold<int>(0, (sum, s) => sum + s.topics.length);

  void _syncCurrent() {
    if (!mounted) return;
    String? top;
    double best = double.infinity;
    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < 160 && y > -box.size.height) {
        final distance = (y - 160).abs();
        if (distance < best) {
          best = distance;
          top = entry.key;
        }
      }
    }
    if (top != null) _current.value = top;
  }

  Future<void> _jumpTo(String anchor) async {
    final target = _keys[anchor]?.currentContext;
    if (target == null || !target.mounted) return;
    _current.value = anchor;
    await Scrollable.ensureVisible(
      target,
      duration: AppDesign.motionStandard,
      curve: AppDesign.curveStandard,
      alignment: 0.02,
    );
  }

  Future<void> _copyLink(GuideTopic topic) async {
    final path = AppRoutes.pathForTool(AppTool.guide) ?? '/guide';
    await Clipboard.setData(
        ClipboardData(text: '${AppRoutes.origin}$path#${topic.anchor}'));
    AppToast.showSuccess('Link to "${topic.title}" copied');
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.auto_stories_outlined,
          title: 'How Tabulr works',
          subtitle: 'Every feature, with the real thing on screen',
        ),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) _rail(context),
              Expanded(
                child: Column(
                  children: [
                    _controls(context, wide),
                    Expanded(
                      child: visible.isEmpty
                          ? _noResults(context)
                          : SingleChildScrollView(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(
                                AppDesign.spacingMd,
                                0,
                                AppDesign.spacingMd,
                                AppDesign.spacingXxl,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final section in visible)
                                    _sectionBlock(context, section),
                                  _footer(context),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 232,
      margin: const EdgeInsets.fromLTRB(
          AppDesign.spacingMd, AppDesign.spacingMd, 0, AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
        children: [
          for (final section in guideSections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd,
                  AppDesign.spacingSm, AppDesign.spacingSm, AppDesign.spacingXs),
              child: Row(
                children: [
                  Icon(section.icon, size: 14, color: scheme.primary),
                  const SizedBox(width: AppDesign.spacingSm),
                  Expanded(
                    child: Text(
                      section.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final topic in section.topics)
              _railItem(context, topic),
          ],
        ],
      ),
    );
  }

  Widget _railItem(BuildContext context, GuideTopic topic) {
    return ValueListenableBuilder<String?>(
      valueListenable: _current,
      builder: (context, current, _) =>
          _railTile(context, topic, current == topic.anchor),
    );
  }

  Widget _railTile(BuildContext context, GuideTopic topic, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return AppTappable(
      onTap: () => _jumpTo(topic.anchor),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, 7, 10, 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              width: 2,
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          topic.title,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, AppDesign.spacingMd,
          AppDesign.spacingMd, AppDesign.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search — clash, share code, minors, exam seat…',
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          if (!wide) ...[
            const SizedBox(height: AppDesign.spacingSm),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final section in guideSections)
                    Padding(
                      padding: const EdgeInsets.only(right: AppDesign.spacingSm),
                      child: ActionChip(
                        avatar: Icon(section.icon, size: 15),
                        label: Text(section.title),
                        onPressed: () => _jumpTo(section.topics.first.anchor),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_query.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Text(
              '$_resultCount ${_resultCount == 1 ? 'topic' : 'topics'} for "$_query"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionBlock(BuildContext context, GuideSection section) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppDesign.spacingXs, AppDesign.spacingXl, 0, AppDesign.spacingXs),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: scheme.primary),
              const SizedBox(width: AppDesign.spacingSm),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
              left: AppDesign.spacingXs, bottom: AppDesign.spacingSm),
          child: Text(
            section.blurb,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppDesign.muted(context),
            ),
          ),
        ),
        for (final topic in section.topics) _topicCard(context, topic),
      ],
    );
  }

  Widget _topicCard(BuildContext context, GuideTopic topic) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: _keys[topic.anchor],
      margin: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Icon(topic.icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: AppDesign.spacingSm + 2),
              Expanded(
                child: Text(
                  topic.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.link, size: 17),
                tooltip: 'Copy link to this section',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copyLink(topic),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm + 2),
          Text(
            topic.lead,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
          ),
          if (topic.steps.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingMd),
            for (final (i, step) in topic.steps.indexed)
              _step(context, i + 1, step),
          ],
          if (topic.pageInfo != null) _features(context, topic.pageInfo!),
          for (final visual in topic.visuals)
            GuideVisualFrame(visual: visual, enabled: _showVisuals),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: AppDesign.spacingSm + 2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _features(BuildContext context, PageInfo info) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spacingMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spacingMd, vertical: AppDesign.spacingSm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: AppDesign.borderRadiusMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, feature) in info.features.indexed) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.3)),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(feature.icon,
                        size: 15,
                        color: scheme.primary.withValues(alpha: 0.8)),
                    const SizedBox(width: AppDesign.spacingSm + 2),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${feature.label}  ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: feature.description,
                              style: TextStyle(
                                color:
                                    scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noResults(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'Nothing matches "$_query"',
      subtitle: 'Try a different word — "clash", "share", "minor", "seat".',
      actionLabel: 'Clear search',
      actionIcon: Icons.close,
      onAction: () => setState(() {
        _search.clear();
        _query = '';
      }),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spacingLg),
      child: Text(
        'Something here out of date, or a feature missing? Report it from the '
        'Bug Report screen — the guide is part of the app, so it gets fixed the '
        'same way.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppDesign.muted(context),
              height: 1.5,
            ),
      ),
    );
  }
}
