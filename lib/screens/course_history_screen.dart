import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../models/course_history.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_history_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/debouncer.dart';
import '../utils/design_constants.dart';
import '../utils/name_utils.dart';
import '../utils/page_info_helper.dart';
import '../widgets/campus_selector_widget.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_dropdown.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/common/shimmer_loading.dart';

/// Which side of the record you're reading it from.
enum _Lens { courses, professors }

/// Course filters, phrased as the question a student is actually asking.
enum _CourseFilter {
  all('All'),
  offered('Offered now'),
  paused('Not offered now'),
  fresh('New this sem');

  const _CourseFilter(this.label);
  final String label;
}

enum _CourseSort {
  code('Course code'),
  recent('Recently offered'),
  gap('Longest gap'),
  frequency('Most offered');

  const _CourseSort(this.label);
  final String label;
}

enum _ProfSort {
  name('Name'),
  courses('Most courses'),
  recent('Recently taught');

  const _ProfSort(this.label);
  final String label;
}

/// Every semester on record, from the campus's own timetable uploads: which
/// courses ran, who taught them, and how long it has been.
///
/// Two lenses on one dataset rather than two screens, because the questions run
/// in both directions — "who has taught CS F211" and "what does she teach" are
/// the same rows read from opposite ends, and the sheets cross-link so either
/// answer leads to the other.
class CourseHistoryScreen extends StatefulWidget {
  const CourseHistoryScreen({super.key});

  @override
  State<CourseHistoryScreen> createState() => _CourseHistoryScreenState();
}

class _CourseHistoryScreenState extends State<CourseHistoryScreen> {
  final CourseHistoryService _service = CourseHistoryService();
  // The app's only source of course titles; the history bundle stores none.
  final CoursesMasterService _master = CoursesMasterService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _searchDebounce = Debouncer(duration: const Duration(milliseconds: 250));

  _Lens _lens = _Lens.courses;
  _CourseFilter _filter = _CourseFilter.all;
  _CourseSort _courseSort = _CourseSort.code;
  _ProfSort _profSort = _ProfSort.name;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      _searchDebounce.run(() {
        if (!mounted) return;
        setState(() => _query = _searchController.text.trim().toLowerCase());
      });
    });
  }

  /// The catalogue is loaded here rather than assumed: this screen has its own
  /// URL and is open to guests, so it can be the first thing the app opens.
  Future<void> _load() async {
    await Future.wait([_service.load(), _master.loadForCampus()]);
    if (mounted) setState(() {});
  }

  /// The curated title, or the bare code when the catalogue has no row for it —
  /// the same fallback every other screen shows.
  String _titleOf(String courseCode) {
    final title = _master.getTitle(courseCode);
    return title == courseCode ? '' : title;
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _query = '');
  }

  // ── Filtering and sorting ────────────────────────────────────────────────

  List<CourseTimeline> _visibleCourses(CourseHistory history) {
    final terms = history.terms;
    final current = history.currentTerm;
    final courses = history.courses.where((course) {
      if (_query.isNotEmpty &&
          !course.courseCode.toLowerCase().contains(_query) &&
          !_titleOf(course.courseCode).toLowerCase().contains(_query)) {
        return false;
      }
      return switch (_filter) {
        _CourseFilter.all => true,
        _CourseFilter.offered => course.lastOfferedTerm == current,
        _CourseFilter.paused => course.lastOfferedTerm != current,
        _CourseFilter.fresh => course.isNewIn(terms),
      };
    }).toList();

    courses.sort(switch (_courseSort) {
      _CourseSort.code => (a, b) => a.courseCode.compareTo(b.courseCode),
      // Ties broken by code throughout, so the order is stable rather than
      // whatever the previous sort happened to leave behind.
      _CourseSort.recent => (a, b) {
          final byTerm = b.lastOfferedTerm.compareTo(a.lastOfferedTerm);
          return byTerm != 0 ? byTerm : a.courseCode.compareTo(b.courseCode);
        },
      _CourseSort.gap => (a, b) {
          final byTerm = a.lastOfferedTerm.compareTo(b.lastOfferedTerm);
          return byTerm != 0 ? byTerm : a.courseCode.compareTo(b.courseCode);
        },
      _CourseSort.frequency => (a, b) {
          final byCount = b.timesOffered.compareTo(a.timesOffered);
          return byCount != 0 ? byCount : a.courseCode.compareTo(b.courseCode);
        },
    });
    return courses;
  }

  List<InstructorTimeline> _visibleProfessors(CourseHistory history) {
    final professors = history.instructors
        .where((prof) => _query.isEmpty || prof.searchText.contains(_query))
        .toList();

    professors.sort(switch (_profSort) {
      _ProfSort.name => (a, b) => a.name.compareTo(b.name),
      _ProfSort.courses => (a, b) {
          final byCount = b.courses.length.compareTo(a.courses.length);
          return byCount != 0 ? byCount : a.name.compareTo(b.name);
        },
      _ProfSort.recent => (a, b) {
          final byTerm = b.lastActiveTerm.compareTo(a.lastActiveTerm);
          return byTerm != 0 ? byTerm : a.name.compareTo(b.name);
        },
    });
    return professors;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        // Three actions leave a phone's toolbar no room for the icon chip and a
        // subtitle; the semester count moves into the axis label instead.
        title: ResponsiveService.isMobile(context) ? 'Course History' : null,
        titleWidget: ResponsiveService.isMobile(context)
            ? null
            : ListenableBuilder(
                listenable: _service,
                builder: (context, _) {
                  final terms = _service.history.terms.length;
                  return AppDesign.iconTitle(
                    context,
                    icon: Icons.history_toggle_off,
                    title: 'Course History',
                    subtitle: terms == 0
                        ? 'Past semesters'
                        : '$terms semester${terms == 1 ? '' : 's'} on record',
                  );
                },
              ),
        centerTitle: false,
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.courseHistory),
          CampusSelectorWidget(
            onCampusChanged: (campus) {
              ToastService.showInfo(
                'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
              );
              _master.clear();
              _load();
            },
          ),
          const SizedBox(width: AppDesign.spacingXs),
          if (kIsWeb)
            IconButton(
              onPressed: () async {
                await _service.refresh();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          if (_service.isLoading) return const CourseListSkeleton();
          if (_service.error != null) return _errorView();
          if (_service.history.isEmpty) return _noHistoryView();
          return _content(_service.history);
        },
      ),
    );
  }

  Widget _errorView() {
    return EmptyStateWidget(
      icon: Icons.cloud_off,
      title: "Couldn't load course history",
      subtitle: _service.error,
      actionLabel: 'Try again',
      actionIcon: Icons.refresh,
      onAction: _service.refresh,
    );
  }

  Widget _noHistoryView() {
    return EmptyStateWidget(
      icon: Icons.history_toggle_off,
      title: 'No history yet for '
          '${CampusService.currentCampusDisplayName}',
      subtitle: 'A semester joins the record when its timetable is uploaded, so '
          'this fills in from here. Try another campus in the meantime.',
    );
  }

  /// Capped and centred. The row is three narrow columns — code, strip, pill —
  /// and left to fill a desktop window it stretched a thousand pixels of dead
  /// space between the course name and its own timeline.
  static const double _maxContentWidth = 860;

  Widget _content(CourseHistory history) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: Column(
          children: [
            _controls(),
            Expanded(
              child: _lens == _Lens.courses
                  ? _courseList(history)
                  : _professorList(history),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final isMobile = ResponsiveService.isMobile(context);
    final searchField = AppSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hint: _lens == _Lens.courses
          ? 'Search a course code or name'
          : 'Search a professor',
      onSubmitted: (_) => _searchFocusNode.unfocus(),
      onClear: _clearSearch,
    );
    // Sort rides with the search field rather than with the filter chips: the
    // chips need the whole width to themselves, and at phone width sharing a row
    // with them clipped "Not offered now" mid-word.
    final sort = _lens == _Lens.courses
        ? _sortPicker<_CourseSort>(
            value: _courseSort,
            values: _CourseSort.values,
            labelOf: (option) => option.label,
            onChanged: (option) => setState(() => _courseSort = option),
          )
        : _sortPicker<_ProfSort>(
            value: _profSort,
            values: _ProfSort.values,
            labelOf: (option) => option.label,
            onChanged: (option) => setState(() => _profSort = option),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDesign.spacingMd, AppDesign.spacingSm + 4, AppDesign.spacingMd, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Below the tablet breakpoint the lens toggle and the field cannot
          // share a row without the field shrinking to a few characters.
          if (isMobile) ...[
            _lensToggle(),
            const SizedBox(height: AppDesign.spacingSm),
            Row(children: [
              Expanded(child: searchField),
              const SizedBox(width: AppDesign.spacingSm),
              sort,
            ]),
          ] else
            Row(
              children: [
                _lensToggle(),
                const SizedBox(width: AppDesign.spacingMd),
                Expanded(child: searchField),
                const SizedBox(width: AppDesign.spacingSm + 4),
                sort,
              ],
            ),
          if (_lens == _Lens.courses) ...[
            const SizedBox(height: AppDesign.spacingSm + 4),
            _filterChips(),
          ],
        ],
      ),
    );
  }

  Widget _lensToggle() {
    return SegmentedButton<_Lens>(
      segments: const [
        ButtonSegment(
          value: _Lens.courses,
          label: Text('Courses'),
          icon: Icon(Icons.menu_book_outlined, size: AppDesign.iconSizeSm),
        ),
        ButtonSegment(
          value: _Lens.professors,
          label: Text('Professors'),
          icon: Icon(Icons.person_search_outlined, size: AppDesign.iconSizeSm),
        ),
      ],
      selected: {_lens},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (selection) =>
          setState(() => _lens = selection.first),
    );
  }

  /// Wraps rather than scrolls: four short chips fit on two rows at any width,
  /// and a chip half off the edge reads as broken rather than as scrollable.
  Widget _filterChips() {
    return Wrap(
      spacing: AppDesign.spacingSm,
      runSpacing: AppDesign.spacingSm,
      children: [
        for (final filter in _CourseFilter.values)
          FilterChip(
            label: Text(filter.label),
            selected: _filter == filter,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _filter = filter),
          ),
      ],
    );
  }

  Widget _sortPicker<T extends Enum>({
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required void Function(T) onChanged,
  }) {
    return AppDropdown<T>(
      value: value,
      // Fixed, so switching lens or sort option doesn't reflow the row it
      // shares with the search field.
      width: 168,
      height: 48,
      isExpanded: true,
      icon: const Icon(Icons.sort, size: AppDesign.iconSizeSm),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(labelOf(option))),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }

  /// The two fixed columns. Narrower on a phone, where the course name would
  /// otherwise be squeezed to nothing — and at 150 the row overflowed outright.
  double get _stripWidth => ResponsiveService.isMobile(context) ? 96 : 150;
  double get _recencyWidth => ResponsiveService.isMobile(context) ? 100 : 118;

  // ── Courses ──────────────────────────────────────────────────────────────

  Widget _courseList(CourseHistory history) {
    final courses = _visibleCourses(history);
    if (courses.isEmpty) return _noMatchesView();

    return Column(
      children: [
        _timelineAxis(history, leading: 'COURSE', trailing: 'LAST OFFERED'),
        Expanded(
          child: ListView.builder(
            scrollCacheExtent: ScrollCacheExtent.pixels(800),
            padding: const EdgeInsets.only(bottom: AppDesign.spacingMd),
            itemCount: courses.length,
            itemBuilder: (context, index) =>
                _courseRow(history, courses[index], index),
          ),
        ),
      ],
    );
  }

  Widget _courseRow(CourseHistory history, CourseTimeline course, int index) {
    final scheme = Theme.of(context).colorScheme;
    final termsAgo = course.termsSinceOffered(history.terms);

    return AppTappable(
      onTap: () => _showCourseSheet(history, course),
      // Opaque, not deferToChild: the row's own gaps — between the title and
      // the strip, and either side of the pill — are most of its area, and a
      // row that only responds where there happens to be text feels broken.
      behavior: HitTestBehavior.opaque,
      child: Container(
        // A faint banded background rather than grid lines: the eye has to
        // follow one course across three columns, and boxing every cell in a
        // list this dense is noise.
        color: index.isEven
            ? scheme.surfaceContainerLow.withValues(alpha: 0.5)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spacingMd, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(course.courseCode,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      if (course.isNewIn(history.terms)) ...[
                        const SizedBox(width: AppDesign.spacingSm),
                        _tag('New', scheme.tertiary),
                      ],
                    ],
                  ),
                  if (_titleOf(course.courseCode).isNotEmpty)
                    Text(
                      _titleOf(course.courseCode),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.62)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppDesign.spacingSm),
            _TermStrip(
              width: _stripWidth,
              terms: history.terms,
              activeTerms: {for (final o in course.offerings) o.term},
              tooltipFor: (term) {
                final offering = course.offeringIn(term);
                return offering == null
                    ? '${Terms.label(term)} — not offered'
                    : '${Terms.label(term)} — ${offering.sections} '
                        'section${offering.sections == 1 ? '' : 's'}';
              },
            ),
            const SizedBox(width: AppDesign.spacingSm + 4),
            SizedBox(
              width: _recencyWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: _recencyPill(termsAgo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Professors ───────────────────────────────────────────────────────────

  Widget _professorList(CourseHistory history) {
    final professors = _visibleProfessors(history);
    if (professors.isEmpty) return _noMatchesView();

    return Column(
      children: [
        _timelineAxis(history, leading: 'PROFESSOR', trailing: 'LAST TAUGHT'),
        Expanded(
          child: ListView.builder(
            scrollCacheExtent: ScrollCacheExtent.pixels(800),
            padding: const EdgeInsets.only(bottom: AppDesign.spacingMd),
            itemCount: professors.length,
            itemBuilder: (context, index) =>
                _professorRow(history, professors[index], index),
          ),
        ),
      ],
    );
  }

  Widget _professorRow(
      CourseHistory history, InstructorTimeline prof, int index) {
    final scheme = Theme.of(context).colorScheme;
    final courses = prof.courses.length;
    final terms = prof.terms.length;

    return AppTappable(
      onTap: () => _showProfessorSheet(history, prof),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: index.isEven
            ? scheme.surfaceContainerLow.withValues(alpha: 0.5)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spacingMd, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(prof.displayName,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(
                    '$courses course${courses == 1 ? '' : 's'} · '
                    '$terms semester${terms == 1 ? '' : 's'}'
                    // Running a course is a different thing from teaching a
                    // section of one, and only worth saying when they did.
                    '${prof.everInCharge.isEmpty ? '' : ' · ${prof.everInCharge.length} as IC'}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface.withValues(alpha: 0.62)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDesign.spacingSm),
            _TermStrip(
              width: _stripWidth,
              terms: history.terms,
              activeTerms: prof.coursesByTerm.keys.toSet(),
              tooltipFor: (term) {
                final taught = prof.coursesByTerm[term];
                return taught == null
                    ? '${Terms.label(term)} — nothing on record'
                    : '${Terms.label(term)} — ${taught.join(', ')}';
              },
            ),
            const SizedBox(width: AppDesign.spacingSm + 4),
            SizedBox(
              width: _recencyWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: _recencyPill(prof.termsSinceActive(history.terms)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared pieces ────────────────────────────────────────────────────────

  /// Column labels, plus the two ends of the timeline so the strip below reads
  /// as an axis rather than a row of unexplained boxes.
  Widget _timelineAxis(CourseHistory history,
      {required String leading, required String trailing}) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: scheme.onSurface.withValues(alpha: 0.5),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDesign.spacingMd, AppDesign.spacingMd, AppDesign.spacingMd, 6),
      child: Row(
        children: [
          Expanded(child: Text(leading, style: labelStyle)),
          const SizedBox(width: AppDesign.spacingSm),
          SizedBox(
            width: _stripWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Terms.tickLabel(history.terms.first), style: labelStyle),
                if (history.terms.length > 1)
                  Text('NOW', style: labelStyle),
              ],
            ),
          ),
          const SizedBox(width: AppDesign.spacingSm + 4),
          SizedBox(
            width: _recencyWidth,
            child: Text(trailing,
                textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }

  /// How long ago, as a word plus a hue. Never hue alone — greys differ by a
  /// couple of percent between themes and colour is not readable to everyone.
  Widget _recencyPill(int termsAgo) {
    final colour = switch (termsAgo) {
      <= 0 => AppDesign.success(context),
      1 => AppDesign.info(context),
      _ => AppDesign.warning(context),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppDesign.spacingSm, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: AppDesign.borderRadiusSm,
      ),
      child: Text(
        Terms.relative(termsAgo),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: colour),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tag(String label, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: AppDesign.borderRadiusXs,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: colour)),
    );
  }

  Widget _noMatchesView() {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'Nothing matches',
      subtitle: _query.isEmpty
          ? 'No course fits this filter. Try "All".'
          : 'No ${_lens == _Lens.courses ? 'course' : 'professor'} matches '
              '"${_searchController.text.trim()}".',
      actionLabel: _query.isEmpty ? null : 'Clear search',
      actionIcon: Icons.clear,
      onAction: _query.isEmpty ? null : _clearSearch,
    );
  }

  // ── Detail sheets ────────────────────────────────────────────────────────

  /// Every term, including the ones it did not run in — the gaps are the answer
  /// to "is this coming back", so they get a row of their own rather than being
  /// left out of the list.
  Future<void> _showCourseSheet(
      CourseHistory history, CourseTimeline course) async {
    final scheme = Theme.of(context).colorScheme;
    final jumpTo = await AppDialog.adaptive<String>(
      context: context,
      icon: Icons.menu_book_outlined,
      title: course.courseCode,
      content: _sheetBody(
        header: _titleOf(course.courseCode),
        children: [
          for (final term in history.terms.reversed)
            _courseTermRow(history, course, term, scheme),
        ],
      ),
    );
    if (jumpTo != null && mounted) _openProfessorNamed(history, jumpTo);
  }

  Widget _courseTermRow(CourseHistory history, CourseTimeline course,
      String term, ColorScheme scheme) {
    final offering = course.offeringIn(term);
    final isCurrent = term == history.currentTerm;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(Terms.label(term),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: offering == null
                        ? scheme.onSurface.withValues(alpha: 0.55)
                        : scheme.onSurface,
                  )),
              if (isCurrent) ...[
                const SizedBox(width: AppDesign.spacingSm),
                _tag('NOW', scheme.primary),
              ],
            ],
          ),
          const SizedBox(height: 3),
          if (offering == null)
            Text('Not offered',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.55)))
          else ...[
            Text(
              '${offering.sections} '
              'section${offering.sections == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.75)),
            ),
            if (offering.instructors.isNotEmpty) ...[
              const SizedBox(height: AppDesign.spacingSm),
              // Wrapped, never truncated: the instructor is what a student picks
              // a section on, and every name is tappable through to that
              // professor's own record. Whoever ran the course leads the list
              // and carries the badge.
              Wrap(
                spacing: AppDesign.spacingSm - 2,
                runSpacing: AppDesign.spacingSm - 2,
                children: [
                  for (final name in offering.inCharge)
                    _linkChip(
                        value: name,
                        display: titleCaseName(name),
                        inCharge: true),
                  for (final name in offering.supporting)
                    _linkChip(value: name, display: titleCaseName(name)),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _showProfessorSheet(
      CourseHistory history, InstructorTimeline prof) async {
    final scheme = Theme.of(context).colorScheme;
    final courses = prof.courses.length;
    final jumpTo = await AppDialog.adaptive<String>(
      context: context,
      icon: Icons.person_search_outlined,
      title: prof.displayName,
      content: _sheetBody(
        header: '$courses course${courses == 1 ? '' : 's'} across '
            '${prof.terms.length} semester${prof.terms.length == 1 ? '' : 's'}',
        children: [
          for (final term in history.terms.reversed)
            _profTermRow(history, prof, term, scheme),
        ],
      ),
    );
    if (jumpTo != null && mounted) _openCourseNamed(history, jumpTo);
  }

  Widget _profTermRow(CourseHistory history, InstructorTimeline prof,
      String term, ColorScheme scheme) {
    final taught = prof.coursesByTerm[term];
    final isCurrent = term == history.currentTerm;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(Terms.label(term),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: taught == null
                        ? scheme.onSurface.withValues(alpha: 0.55)
                        : scheme.onSurface,
                  )),
              if (isCurrent) ...[
                const SizedBox(width: AppDesign.spacingSm),
                _tag('NOW', scheme.primary),
              ],
            ],
          ),
          const SizedBox(height: 3),
          if (taught == null)
            Text('Nothing on record',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.55)))
          else
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                spacing: AppDesign.spacingSm - 2,
                runSpacing: AppDesign.spacingSm - 2,
                children: [
                  for (final code in taught)
                    _linkChip(
                        value: code,
                        display: code,
                        bold: true,
                        inCharge: prof.wasInChargeOf(term, code)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The sheet's scrollable body. Height-bounded so a professor with fifteen
  /// semesters cannot push a dialog past the screen.
  Widget _sheetBody({required String header, required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: AppDesign.maxDialogWidth,
        maxHeight: ResponsiveService.getScreenHeight(context) * 0.6,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header.isNotEmpty) ...[
              Text(header,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.7))),
              const SizedBox(height: AppDesign.spacingMd),
            ],
            ...children,
          ],
        ),
      ),
    );
  }

  /// A tappable cross-link. [value] is the canonical key the tap returns;
  /// [display] is what it reads as, which differs for instructor names because
  /// those are stored upper-cased.
  ///
  /// [inCharge] marks the instructor-in-charge with a tint AND the letters "IC",
  /// never the tint alone — a chip that differs only in shade is not an answer on
  /// every theme, or to everyone.
  Widget _linkChip({
    required String value,
    required String display,
    bool bold = false,
    bool inCharge = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: EdgeInsets.fromLTRB(inCharge ? 5 : 9, 5, 9, 5),
      decoration: BoxDecoration(
        color: inCharge
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(
            color: inCharge
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inCharge) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: AppDesign.borderRadiusXs,
              ),
              child: Text('IC',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: scheme.primary)),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            display,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: bold || inCharge ? FontWeight.w700 : FontWeight.w600,
                color: inCharge
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
    return AppTappable(
      onTap: () => Navigator.of(context).pop(value),
      child: inCharge
          ? Tooltip(message: 'Instructor-in-charge', child: chip)
          : chip,
    );
  }

  /// Follows a cross-link from a course sheet to the professor it named.
  void _openProfessorNamed(CourseHistory history, String name) {
    for (final prof in history.instructors) {
      if (prof.name == name) {
        setState(() => _lens = _Lens.professors);
        _showProfessorSheet(history, prof);
        return;
      }
    }
  }

  void _openCourseNamed(CourseHistory history, String code) {
    for (final course in history.courses) {
      if (course.courseCode == code) {
        setState(() => _lens = _Lens.courses);
        _showCourseSheet(history, course);
        return;
      }
    }
  }
}

/// Marks semesters the archive has no booklet for — distinct from a semester a
/// course simply was not offered in.
class _GapMark extends StatelessWidget {
  const _GapMark({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'No records for the semesters in between',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
          width: 5,
          child: Center(
            child: Text('/',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
          ),
        ),
      ),
    );
  }
}

/// One cell per semester on record: filled where the course ran (or the
/// professor taught), faint where it did not.
///
/// Fixed overall width with the cells sharing it, so fifteen semesters occupy
/// exactly the same column as five and the row layout never shifts.
class _TermStrip extends StatelessWidget {
  const _TermStrip({
    required this.terms,
    required this.activeTerms,
    required this.tooltipFor,
    required this.width,
  });

  /// Fixed by the caller so every row and the axis above them share one column,
  /// and so eleven semesters occupy exactly the space five did.
  final double width;

  final List<String> terms;
  final Set<String> activeTerms;
  final String Function(String term) tooltipFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: 22,
      child: Row(
        children: [
          for (final (index, term) in terms.indexed) ...[
            // A break where the archive skips semesters, so eleven cells cannot
            // read as eleven consecutive semesters. Hyderabad has no booklet for
            // 2022-23 or 2023-24; leaving those out silently would imply the
            // record is continuous, and drawing them as empty cells would claim
            // nothing ran, which is equally untrue.
            if (index > 0 && !Terms.areConsecutive(terms[index - 1], term))
              _GapMark(colour: scheme.onSurface.withValues(alpha: 0.3)),
            Expanded(
              child: Tooltip(
                message: tooltipFor(term),
                waitDuration: const Duration(milliseconds: 400),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: activeTerms.contains(term)
                        ? scheme.primary.withValues(alpha: 0.85)
                        : scheme.onSurface.withValues(alpha: 0.09),
                    borderRadius: AppDesign.borderRadiusXs,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (term != terms.last) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}
