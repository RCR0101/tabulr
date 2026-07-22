import 'package:flutter/material.dart';
import '../models/faq_content.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/empty_state_widget.dart';

/// Answers to the academic questions students actually ask, distilled from the
/// Academic Regulations and the Bulletin.
///
/// Content lives in [faqCategories]; this screen only presents it. Search runs
/// across questions, answers, bullets and hidden keywords, and a match inside a
/// collapsed answer still surfaces the card — so a term like "compre" finds the
/// evaluation entry even though the word is only in its keywords.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _category; // null = all

  /// Identified by "category · question" so the same question text in two
  /// categories can't share expansion state.
  final Set<String> _expanded = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FaqCategory> get _visible {
    final categories = _category == null
        ? faqCategories
        : faqCategories.where((c) => c.title == _category);

    return [
      for (final c in categories)
        if (c.entries.any((e) => e.matches(_query)))
          FaqCategory(
            title: c.title,
            icon: c.icon,
            entries: c.entries.where((e) => e.matches(_query)).toList(),
          ),
    ];
  }

  int get _resultCount =>
      _visible.fold<int>(0, (sum, c) => sum + c.entries.length);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final searching = _query.isNotEmpty;

    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.help_outline,
          title: 'Academic FAQ',
          subtitle: 'Straight answers from the regulations',
        ),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              _buildControls(context),
              Expanded(
                child: visible.isEmpty
                    ? _noResults(context)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppDesign.spacingMd,
                          0,
                          AppDesign.spacingMd,
                          AppDesign.spacingXl,
                        ),
                        children: [
                          for (final (i, category) in visible.indexed)
                            _buildCategory(context, category, i,
                                autoExpand: searching),
                          _buildFooter(context),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        AppDesign.spacingMd,
        AppDesign.spacingMd,
        AppDesign.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search grades, CGPA, Practice School…',
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: AppDesign.spacingSm),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip(context, null, 'All'),
                for (final c in faqCategories)
                  _categoryChip(context, c.title, c.title, icon: c.icon),
              ],
            ),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Text(
              '$_resultCount ${_resultCount == 1 ? 'answer' : 'answers'} for "$_query"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip(BuildContext context, String? value, String label,
      {IconData? icon}) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: AppDesign.spacingSm),
      child: FilterChip(
        avatar: icon == null
            ? null
            : Icon(icon,
                size: 16,
                color: selected
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : Theme.of(context).colorScheme.onSurface),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _category = selected ? null : value),
      ),
    );
  }

  Widget _buildCategory(BuildContext context, FaqCategory category, int index,
      {required bool autoExpand}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppDesign.spacingXs, AppDesign.spacingMd, 0, AppDesign.spacingSm),
          child: Row(
            children: [
              Icon(category.icon, size: 18, color: scheme.primary),
              const SizedBox(width: AppDesign.spacingSm),
              Text(
                category.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
              ),
            ],
          ),
        ),
        for (final entry in category.entries)
          _buildEntry(context, category, entry, autoExpand: autoExpand),
      ],
    ).motionListItem(index);
  }

  Widget _buildEntry(
    BuildContext context,
    FaqCategory category,
    FaqEntry entry, {
    required bool autoExpand,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final key = '${category.title} · ${entry.question}';
    // While searching, everything opens so matches are readable at a glance;
    // an explicit tap still toggles that individual card.
    final open = _expanded.contains(key) || (autoExpand && !_expanded.contains('!$key'));

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      decoration: AppDesign.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTappable(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(key);
                if (autoExpand) _expanded.add('!$key');
              } else {
                _expanded.add(key);
                _expanded.remove('!$key');
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.question,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spacingSm),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: AppDesign.motionFast,
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDesign.motionFast,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? _answer(context, entry)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _answer(BuildContext context, FaqEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        0,
        AppDesign.spacingMd,
        AppDesign.spacingMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: scheme.outline.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: AppDesign.spacingMd),
          Text(
            entry.answer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
          ),
          if (entry.bullets.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingSm),
            for (final bullet in entry.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.spacingXs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        bullet,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.8),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (entry.source != null) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: AppDesign.borderRadiusSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 13,
                      color: scheme.onSurface.withValues(alpha: 0.55)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      entry.source!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noResults(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'Nothing matches "$_query"',
      subtitle: 'Try a different word, or clear the filters.',
      actionLabel: 'Clear search',
      actionIcon: Icons.close,
      onAction: () => setState(() {
        _search.clear();
        _query = '';
        _category = null;
      }),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spacingLg),
      child: Text(
        'Summarised from the BITS Pilani Academic Regulations and the Bulletin '
        '2025-26. These are short answers — where a decision matters, check the '
        'cited clause in the official document, which always takes precedence.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.45),
              height: 1.5,
            ),
      ),
    );
  }
}
