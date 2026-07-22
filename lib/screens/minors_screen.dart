import 'package:flutter/material.dart';
import '../models/academic_record.dart';
import '../models/course.dart';
import '../models/minor_progress.dart';
import '../models/minor_programme.dart';
import '../models/timetable_selection_link.dart';
import '../services/data/academic_record_service.dart';
import '../services/data/minor_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/course_record_badge.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/elective_course_list.dart';

/// Browsable catalogue of minor programmes.
///
/// Search covers minor names, descriptions and the course lists, so "CS F320"
/// answers "which minors can this course count toward?" — the question a
/// student planning electives actually has.
///
/// When the student has filled in the CGPA calculator this doubles as a
/// tracker: cleared courses are ticked and each minor shows how far along it
/// is. All of that stays hidden for an empty record, so the catalogue reads the
/// same as before for everyone else.
class MinorsScreen extends StatefulWidget {
  /// Set when opened from the editor. Courses the open timetable can actually
  /// offer this semester then gain an add button; without it the catalogue
  /// stays a pure reference, which is what the drawer entry wants.
  final TimetableSelectionLink? selectionLink;

  const MinorsScreen({super.key, this.selectionLink});

  @override
  State<MinorsScreen> createState() => _MinorsScreenState();
}

class _MinorsScreenState extends State<MinorsScreen> {
  final MinorService _service = MinorService();
  final TextEditingController _search = TextEditingController();

  late Future<List<MinorProgramme>> _future;
  String _query = '';
  final Set<String> _expanded = {};

  /// Loaded separately from the catalogue so a slow or failed CGPA fetch never
  /// holds up the minors list — progress just doesn't appear.
  AcademicRecord _record = AcademicRecord.empty;

  /// Codes the open timetable can offer, normalized for lookup. Comes free from
  /// the link's embedded catalogue — no extra fetch.
  late final Map<String, Course> _offered = {
    for (final course in widget.selectionLink?.availableCourses ?? const [])
      AcademicRecord.normalizeCode(course.courseCode): course,
  };

  @override
  void initState() {
    super.initState();
    _future = _service.getMinors();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final record = await AcademicRecordService().load();
    if (mounted) setState(() => _record = record);
  }

  /// Sections for one course, in a sheet. Reuses the elective results list so
  /// clash detection, the credit cap and the Add/Remove behaviour are the same
  /// here as everywhere else.
  void _openSections(Course course) {
    final link = widget.selectionLink!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.spacingMd,
                  vertical: AppDesign.spacingSm,
                ),
                child: ElectiveTimetableBanner(selectionLink: link),
              ),
              Expanded(
                child: ElectiveCourseList(
                  courses: [course],
                  catalog: link.availableCourses,
                  selectionLink: link,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Block body, not an arrow: an arrow returns the assigned value, and
    // setState asserts its callback didn't hand back a Future.
    setState(() {
      _future = _service.getMinors(forceRefresh: true);
    });
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
    final progress = MinorProgress.of(minor, _record);

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
                  // Only for minors actually under way — a "0/5" on all 23
                  // cards would be noise, and tells the student nothing.
                  if (progress.hasStarted) ...[
                    _progressPill(context, progress),
                    const SizedBox(width: AppDesign.spacingSm),
                  ],
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
                ? _details(context, minor, progress)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    ).motionListItem(index);
  }

  /// "3/5" against a thin track — enough to rank minors at a glance without
  /// competing with the minor's name.
  Widget _progressPill(BuildContext context, MinorProgress progress) {
    final scheme = Theme.of(context).colorScheme;
    final done = progress.meetsCourseCount;
    final color = done ? Colors.green.shade600 : scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[
                Icon(Icons.check, size: 12, color: color),
                const SizedBox(width: 3),
              ],
              Text(
                '${progress.clearedCount}/${progress.requiredCourses}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 34,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 3,
                backgroundColor: color.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Progress summary shown inside the expansion, where there is room for the
  /// detail the pill compresses — including the clause 5.02(iv) CGPA floor,
  /// which is measured across the minor's courses, not your overall CGPA.
  Widget _progressSummary(BuildContext context, MinorProgress progress) {
    final scheme = Theme.of(context).colorScheme;
    final meetsCgpa = progress.meetsCgpa;

    final bits = <String>[
      '${progress.clearedCount} of ${progress.requiredCourses} courses cleared',
      if (progress.clearedUnits > 0)
        '${progress.unitsAreComplete ? '' : 'at least '}'
            '${progress.clearedUnits} units',
      if (progress.failed.isNotEmpty)
        '${progress.failed.length} to repeat',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppDesign.spacingMd),
      padding: const EdgeInsets.all(AppDesign.spacingSm),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: AppDesign.borderRadiusSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bits.join('  ·  '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
          ),
          if (progress.cgpaInMinor != null) ...[
            const SizedBox(height: 3),
            Text(
              'CGPA ${progress.cgpaInMinor!.toStringAsFixed(2)} across these '
              '— ${meetsCgpa == true ? 'above' : 'below'} the '
              '${MinorProgress.minimumCgpa.toStringAsFixed(2)} a minor needs.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: meetsCgpa == true
                        ? scheme.onSurface.withValues(alpha: 0.6)
                        : scheme.error,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _details(
      BuildContext context, MinorProgramme minor, MinorProgress progress) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, 0,
          AppDesign.spacingMd, AppDesign.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: scheme.outline.withValues(alpha: 0.15), height: 1),
          if (progress.hasStarted) _progressSummary(context, progress),
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
            for (final course in group.courses) _courseRow(context, course),
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

  // Trailing columns are fixed-width so they line up down the whole list. With
  // intrinsic widths the units drifted left and right row to row, depending on
  // whether that course happened to carry a grade badge.
  static const double _badgeSlot = 44;
  static const double _unitsSlot = 30;
  static const double _actionSlot = 32;

  /// One course line.
  ///
  /// Wide layouts get a single row that reads as a table. Narrow ones move the
  /// title to its own line rather than squeezing it into the ~100px left after
  /// the code and the trailing columns.
  Widget _courseRow(BuildContext context, MinorCourse course) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = ResponsiveService.isMobile(context);

    final code = Text(
      course.code,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
    );

    final title = Text(
      course.title,
      maxLines: narrow ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
    );

    final trailing = [
      // Slots are reserved only when the feature is in play at all, so a
      // student with no record and no open timetable sees no empty gutters.
      if (_record.isNotEmpty)
        SizedBox(
          width: _badgeSlot,
          child: Align(
            alignment: Alignment.centerRight,
            child: CourseRecordBadge(record: _record, courseCode: course.code),
          ),
        ),
      SizedBox(
        width: _unitsSlot,
        child: Text(
          course.units == null ? '' : '${course.units}u',
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
        ),
      ),
      if (widget.selectionLink != null)
        SizedBox(width: _actionSlot, child: _addAction(context, course)),
    ];

    return Padding(
      // Roomier than the admin editor's equivalent: this is a list students
      // read, not one they bulk-edit.
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: code),
                    ...trailing,
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1, bottom: 2),
                  child: title,
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 96, child: code),
                Expanded(child: title),
                ...trailing,
              ],
            ),
    );
  }

  /// Only for courses the open timetable can actually offer this semester —
  /// most of a minor's catalogue isn't running, and a disabled button on every
  /// row would be pure noise. The slot stays reserved either way so the column
  /// doesn't jump.
  Widget _addAction(BuildContext context, MinorCourse course) {
    final offered = _offered[AcademicRecord.normalizeCode(course.code)];
    if (offered == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'Offered this semester — pick a section',
      child: AppTappable(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openSections(offered),
        child: SizedBox(
          height: _actionSlot,
          child: Icon(
            Icons.add_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
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
