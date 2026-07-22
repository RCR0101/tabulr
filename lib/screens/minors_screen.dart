import 'package:flutter/material.dart';
import '../models/minor_programme.dart';
import '../services/data/minor_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/common/shimmer_loading.dart';

/// Browsable catalogue of minor programmes.
///
/// Search covers minor names, descriptions and the course lists, so "CS F320"
/// answers "which minors can this course count toward?" — the question a
/// student planning electives actually has.
class MinorsScreen extends StatefulWidget {
  const MinorsScreen({super.key});

  @override
  State<MinorsScreen> createState() => _MinorsScreenState();
}

class _MinorsScreenState extends State<MinorsScreen> {
  final MinorService _service = MinorService();
  final TextEditingController _search = TextEditingController();

  late Future<List<MinorProgramme>> _future;
  String _query = '';
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _future = _service.getMinors();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = _service.getMinors(forceRefresh: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.workspace_premium_outlined,
          title: 'Minor Programmes',
          subtitle: 'Add focus outside your major',
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: FutureBuilder<List<MinorProgramme>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const TimetableListSkeleton();
              }
              final all = snapshot.data ?? const <MinorProgramme>[];
              if (all.isEmpty) {
                return const EmptyStateWidget(
                  icon: Icons.workspace_premium_outlined,
                  title: 'No minors listed yet',
                  subtitle: 'The catalogue has not been published.',
                );
              }

              final visible =
                  all.where((m) => m.matches(_query)).toList(growable: false);

              return Column(
                children: [
                  _buildHeader(context, all.length),
                  Expanded(
                    child: visible.isEmpty
                        ? _noResults(context)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              AppDesign.spacingMd,
                              0,
                              AppDesign.spacingMd,
                              AppDesign.spacingXl,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, i) =>
                                _minorCard(context, visible[i], i),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int total) {
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
            hint: 'Search a minor, or a course code like CS F320…',
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Container(
            padding: const EdgeInsets.all(AppDesign.spacingSm),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.07),
              borderRadius: AppDesign.borderRadiusSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.primary),
                const SizedBox(width: AppDesign.spacingSm),
                Expanded(
                  child: Text(
                    'Declare a minor at the end of your 2nd year. It needs at least '
                    '5 courses and 15 units, with a CGPA of 4.5 in them. No course '
                    'can count toward two minors.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _minorCard(BuildContext context, MinorProgramme minor, int index) {
    final scheme = Theme.of(context).colorScheme;
    final open = _expanded.contains(minor.id);

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
              if (!_expanded.remove(minor.id)) _expanded.add(minor.id);
            }),
            child: Padding(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          minor.name,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (minor.minCourses != null)
                              '${minor.minCourses} courses min',
                            if (minor.minUnits != null)
                              '${minor.minUnits} units min',
                            '${minor.courseCount} listed',
                          ].join('  ·  '),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.55),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: AppDesign.motionFast,
                    curve: Curves.easeOut,
                    child: Icon(Icons.expand_more,
                        size: 20,
                        color: scheme.onSurface.withValues(alpha: 0.5)),
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
                ? _details(context, minor)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    ).motionListItem(index);
  }

  Widget _details(BuildContext context, MinorProgramme minor) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, 0,
          AppDesign.spacingMd, AppDesign.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: scheme.outline.withValues(alpha: 0.15), height: 1),
          if (minor.description.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingMd),
            Text(
              minor.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ],
          for (final group in minor.groups) ...[
            const SizedBox(height: AppDesign.spacingMd),
            Text(
              group.name.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: scheme.primary,
                  ),
            ),
            const SizedBox(height: AppDesign.spacingXs),
            for (final course in group.courses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        course.code,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.85),
                                ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        course.title,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                      ),
                    ),
                    if (course.units != null)
                      Text(
                        '${course.units}u',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppDesign.spacingSm),
          Text(
            'From the BITS Bulletin. Confirm against the current Bulletin before '
            'planning around it.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
          ),
        ],
      ),
    );
  }

  Widget _noResults(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'No minor matches "$_query"',
      subtitle: 'Try a minor name or a course code.',
      actionLabel: 'Clear search',
      actionIcon: Icons.close,
      onAction: () => setState(() {
        _search.clear();
        _query = '';
      }),
    );
  }
}
