import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/course.dart';
import '../models/elective_pool.dart';
import '../models/timetable_selection_link.dart';
import '../services/core/clash_detector.dart';
import '../services/data/campus_service.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/course_data_service.dart';
import '../services/data/discipline_electives_service.dart';
import '../services/data/humanities_electives_service.dart';
import '../services/data/open_electives_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/branch_constants.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_dropdown.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/inline_error_card.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/elective_course_list.dart';

/// Per-pool results. Each tab loads on first view and then only when the shared
/// branch/semester selection changes, so switching tabs is instant.
class _PoolState {
  List<Course> courses = const [];
  bool loading = false;
  bool loaded = false;
  String error = '';
  String query = '';

  /// Electives that exist for the branch but are not offered this semester.
  /// Discipline only; shown as a footnote rather than hidden silently.
  int unavailable = 0;

  void reset() {
    courses = const [];
    loaded = false;
    error = '';
    unavailable = 0;
  }
}

/// One browser for all three elective pools.
///
/// Replaces three near-identical screens that each asked for the same branch
/// and semester before showing anything, and each rendered the branch
/// differently (Humanities showed the bare code, the other two the bare name).
/// Branch and semester are picked once here and shared across the tabs; only
/// the pool changes.
class ElectivesScreen extends StatefulWidget {
  /// Set when opened from the editor, which makes the results writable —
  /// Add/Remove goes straight onto that timetable. Null elsewhere (the
  /// timetable list, the command palette), leaving the screen read-only.
  final TimetableSelectionLink? selectionLink;

  /// Which tab to open on. Kept so entry points can still be pool-specific.
  final ElectivePool initialPool;

  const ElectivesScreen({
    super.key,
    this.selectionLink,
    this.initialPool = ElectivePool.discipline,
  });

  @override
  State<ElectivesScreen> createState() => _ElectivesScreenState();
}

class _ElectivesScreenState extends State<ElectivesScreen>
    with SingleTickerProviderStateMixin {
  // `late final`, not eager: these services build Firestore references in their
  // own field initializers, so constructing them here would demand Firebase be
  // up the moment this State is created — during build, where the throw cannot
  // be caught. Deferring to first use puts it inside _loadInitialData's guard,
  // which turns it into an error card instead of a crashed frame.
  late final _disciplineService = DisciplineElectivesService();
  late final _humanitiesService = HumanitiesElectivesService();
  late final _openService = OpenElectivesService();
  late final _courseData = CourseDataService();
  late final _branchStructure = BranchStructureService();

  late final TabController _tabs;
  final _search = TextEditingController();

  List<BranchInfo> _branches = const [];
  List<Course> _catalog = const [];

  BranchInfo? _primary;
  BranchInfo? _secondary;
  String? _semester;

  bool _loading = true;
  String _loadError = '';
  StreamSubscription<Campus>? _campusSub;

  // Bumped per load; a stale campus-change reload that finishes late compares
  // unequal and drops its result instead of overwriting fresher data.
  int _loadSeq = 0;

  final _pools = {for (final p in ElectivePool.values) p: _PoolState()};

  /// Hide discipline electives that clash with the student's core courses.
  ///
  /// On by default because that is what the old screen always did — silently,
  /// with no way to see what had been removed. Only Discipline can answer this:
  /// the clash is against the CDCs for a branch and semester, and no equivalent
  /// exists for the humanities or open pools.
  bool _hideCoreClashes = true;

  /// The CDCs for the chosen branch(es) and semester, resolved to courses.
  ///
  /// Shared by all three tabs: a HUEL or an OPEL sits alongside exactly the
  /// same core courses a DEL does, so it can clash with them in exactly the
  /// same way. This used to be computed inside the discipline service and
  /// applied to that pool only — an artefact of where the method was written,
  /// not a property of the pools.
  List<Course> _coreCourses = const [];

  ElectivePool get _pool => ElectivePool.values[_tabs.index];
  _PoolState get _current => _pools[_pool]!;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: ElectivePool.values.length,
      vsync: this,
      initialIndex: widget.initialPool.index,
    )..addListener(_onTabChanged);
    _loadInitialData();
    _campusSub =
        CampusService.campusChangeStream.listen((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _search.dispose();
    _campusSub?.cancel();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    // The search box is per-pool; restore this tab's own query.
    _search.text = _current.query;
    setState(() {});
    _loadPoolIfNeeded();
  }

  Future<void> _loadInitialData() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _loadError = '';
    });
    try {
      final branches = await _disciplineService
          .getAvailableBranches()
          .timeout(AppDurations.shortNetworkTimeout);
      // Linked to a timetable: browse that timetable's embedded catalog, so
      // everything offered here is something it can actually accept.
      final catalog = widget.selectionLink?.availableCourses ??
          await _courseData.fetchCourses();

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _branches = branches;
        _catalog = catalog;
        _loading = false;
        _prefillFromProfile();
        for (final p in _pools.values) {
          p.reset();
        }
      });
      _loadPoolIfNeeded();
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loadError = 'Failed to load electives: $e';
        _loading = false;
      });
    }
  }

  /// Pre-selects the student's saved branches and semester so the screen opens
  /// ready to browse, without overwriting a choice already made.
  void _prefillFromProfile() {
    final profile = ProfileService().cached;
    BranchInfo? byCode(String? code) {
      if (code == null) return null;
      for (final b in _branches) {
        if (b.code == code) return b;
      }
      return null;
    }

    _primary ??= byCode(profile.primaryBranch);
    final secondary = byCode(profile.secondaryBranch);
    if (_secondary == null && secondary != _primary) _secondary = secondary;
    _semester ??= SemesterConstants.electives.first;
  }

  /// Selection changed: every pool's results are now stale.
  void _onSelectionChanged() {
    for (final p in _pools.values) {
      p.reset();
    }
    setState(() {});
    _loadPoolIfNeeded();
  }

  bool get _canBrowse => _primary != null && _semester != null;

  /// Resolves the CDC set for the current selection. Cheap after the first
  /// call — BranchStructureService caches — and shared by every pool.
  Future<void> _loadCoreCourses() async {
    if (_primary == null || _semester == null) {
      _coreCourses = const [];
      return;
    }
    try {
      final codes = await _branchStructure
          .getCoreCourseCodes(
            _semester!,
            _primary!.code,
            _semester,
            _secondary?.code,
          )
          .timeout(AppDurations.shortNetworkTimeout);
      _coreCourses =
          _catalog.where((c) => codes.contains(c.courseCode)).toList();
    } catch (_) {
      // Advisory: without the CDC list the clash filter simply has less to
      // check, which must not break browsing.
      _coreCourses = const [];
    }
  }

  Future<void> _loadPoolIfNeeded() async {
    final pool = _pool;
    final state = _pools[pool]!;
    if (state.loaded || state.loading || !_canBrowse) return;

    setState(() {
      state.loading = true;
      state.error = '';
    });

    try {
      await _loadCoreCourses();
      final (courses, unavailable) = await _fetch(pool);
      if (!mounted || _pools[pool] != state) return;
      setState(() {
        state.courses = courses;
        state.unavailable = unavailable;
        state.loading = false;
        state.loaded = true;
        if (courses.isEmpty) {
          state.error = 'No ${pool.short} courses found for this selection.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        state.loading = false;
        state.loaded = true;
        state.error =
            'Unable to load ${pool.short} courses right now. Please try again.';
      });
    }
  }

  /// Returns the pool's courses plus, for Discipline, how many electives exist
  /// for the branch but are not offered this semester.
  Future<(List<Course>, int)> _fetch(ElectivePool pool) async {
    switch (pool) {
      case ElectivePool.discipline:
        // Deliberately the unfiltered call. The clash-filtering variant compares
        // only like section types, so an elective lecture on a core practical
        // slipped through it — and it applied to this pool alone. _dropClashes
        // below does the job for all three, type-agnostically.
        final electives = await _disciplineService
            .getFilteredDisciplineElectives(
              _primary!.code,
              _secondary?.code,
              _catalog,
            )
            .timeout(AppDurations.networkTimeout);
        final courses = electives
            .map((e) => _disciplineService.getCourseDetails(e.courseCode, _catalog))
            .whereType<Course>()
            .toList();
        return (courses, electives.length - courses.length);

      case ElectivePool.humanities:
        final courses = await _humanitiesService
            .getFilteredHumanitiesElectives(
              _semester!,
              _primary!.code,
              _semester,
              _secondary?.code,
              _catalog,
            )
            .timeout(AppDurations.networkTimeout);
        return (courses, 0);

      case ElectivePool.open:
        final courses = await _openService
            .getOpenElectives(_catalog, [
              _primary!.code,
              if (_secondary != null) _secondary!.code,
            ])
            .timeout(AppDurations.networkTimeout);
        return (courses, 0);
    }
  }

  /// Drops courses that cannot be taken alongside the student's core courses,
  /// or alongside what is already on the open timetable.
  ///
  /// One check for all three pools. A HUEL or an OPEL clashes with a CDC in
  /// exactly the way a DEL does; the old split — core-clash filtering built
  /// into the discipline service and nowhere else — reflected where the code
  /// happened to live, not the domain.
  ///
  /// Type-agnostic, unlike the service filter it replaces: a lecture landing on
  /// someone else's practical is a clash too.
  ///
  /// Two kinds of obstacle, treated differently because they differ in kind:
  /// a section already ON the timetable is fixed, so any collision with it is
  /// real; a CDC's section is NOT yet chosen, so a collision only counts when
  /// every section of that component collides.
  ///
  /// Course-level: a course survives if each component it offers still has a
  /// takeable section. Individual clashing sections stay visible and greyed, so
  /// the student sees the trade-off rather than the course silently vanishing.
  List<Course> _dropClashes(List<Course> courses) {
    final selected = widget.selectionLink?.selectedSections ?? const [];

    // A CDC's sections grouped by component, per course. The student must take
    // ONE section of each component, but has not chosen which — so a single
    // collision proves nothing. Only "every section of this component
    // collides" makes the elective genuinely untakeable.
    final coreComponents = <List<Section>>[];
    for (final core in _coreCourses) {
      final byType = <SectionType, List<Section>>{};
      for (final section in core.sections) {
        (byType[section.type] ??= []).add(section);
      }
      coreComponents.addAll(byType.values);
    }

    final examBlockers = <Course>[
      ..._coreCourses,
      for (final code in selected.map((s) => s.courseCode).toSet())
        ..._catalog.where((c) => c.courseCode == code),
    ];

    if (coreComponents.isEmpty && selected.isEmpty) return courses;

    /// Whether this section cannot be taken, whatever else the student picks.
    bool blocked(Section section, String courseCode) {
      // Already on the timetable: that section is fixed, so any collision with
      // it is real.
      for (final sel in selected) {
        if (sel.courseCode == courseCode) continue;
        if (ClashDetector.sectionsConflict(section, sel.section)) return true;
      }
      // A CDC component: unavoidable only if EVERY section of it collides.
      // Colliding with one lecture of a course that offers three is not a
      // clash — the student simply takes one of the other two.
      for (final component in coreComponents) {
        if (component.every(
            (core) => ClashDetector.sectionsConflict(section, core))) {
          return true;
        }
      }
      return false;
    }

    return courses.where((course) {
      // Already on the timetable: never hide it, or Remove becomes unreachable.
      if (selected.any((s) => s.courseCode == course.courseCode)) return true;

      // Exams are fixed for a course regardless of section, so a collision
      // here is always unavoidable.
      for (final other in examBlockers) {
        if (other.courseCode == course.courseCode) continue;
        if (course.midSemExam != null &&
            other.midSemExam != null &&
            ClashDetector.examDatesConflict(
                course.midSemExam!, other.midSemExam!)) {
          return false;
        }
        if (course.endSemExam != null &&
            other.endSemExam != null &&
            ClashDetector.examDatesConflict(
                course.endSemExam!, other.endSemExam!)) {
          return false;
        }
      }

      // The elective survives if each of its own components still has a
      // takeable section.
      final byType = <SectionType, List<Section>>{};
      for (final section in course.sections) {
        (byType[section.type] ??= []).add(section);
      }
      for (final sections in byType.values) {
        if (!sections.any((s) => !blocked(s, course.courseCode))) return false;
      }
      return true;
    }).toList();
  }

  List<Course> get _filtered {
    final state = _current;
    final base =
        _hideCoreClashes ? _dropClashes(state.courses) : state.courses;
    if (state.query.isEmpty) return base;
    final q = state.query.toLowerCase();
    return base
        .where((c) =>
            c.courseCode.toLowerCase().contains(q) ||
            c.courseTitle.toLowerCase().contains(q))
        .toList();
  }

  // ── Selection header ──────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNarrow = ResponsiveService.isMobile(context);

    final fields = <Widget>[
      _field(
        label: 'Branch',
        required: true,
        child: AppDropdown<BranchInfo>(
          isExpanded: true,
          height: _fieldHeight,
          value: _primary,
          hint: Text(_branches.isEmpty ? 'Loading…' : 'Select your branch'),
          items: [
            for (final b in _branches)
              DropdownMenuItem(
                value: b,
                child:
                    Text(branchLabel(b.code), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            _primary = v;
            if (_secondary == v) _secondary = null;
            _onSelectionChanged();
          },
        ),
      ),
      _field(
        label: 'Second branch',
        trailing: _secondary == null
            ? null
            : InkWell(
                onTap: () {
                  _secondary = null;
                  _onSelectionChanged();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Clear',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                ),
              ),
        child: AppDropdown<BranchInfo>(
          isExpanded: true,
          height: _fieldHeight,
          value: _secondary,
          hint: const Text('Optional — dual degree'),
          items: [
            for (final b in _branches.where((b) => b != _primary))
              DropdownMenuItem(
                value: b,
                child:
                    Text(branchLabel(b.code), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            _secondary = v;
            _onSelectionChanged();
          },
        ),
      ),
      _field(
        label: 'Semester',
        // Stays in place but goes inert on Open Electives, so the header does
        // not reflow when switching tabs.
        hint: _pool.membershipVariesBySemester
            ? null
            : 'Used to check clashes with your core courses',
        child: AppDropdown<String>(
          isExpanded: true,
          height: _fieldHeight,
          value: _semester,
          items: [
            for (final s in SemesterConstants.electives)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          // Always live: even where it does not change the pool, it decides
          // which core courses the clash filter compares against.
          onChanged: (v) {
            _semester = v;
            _onSelectionChanged();
          },
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, isNarrow ? 14 : 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        border: Border(
          bottom:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stacked full-width on a phone, side by side once there is room.
          // A Wrap with fixed widths was neither: the fields could not shrink,
          // so they overflowed on narrow screens and still looked cramped.
          if (isNarrow)
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              fields[i],
            ]
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: fields[0]),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: fields[1]),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: fields[2]),
              ],
            ),
          if (widget.selectionLink != null) ...[
            const SizedBox(height: 12),
            ElectiveTimetableBanner(selectionLink: widget.selectionLink),
          ],
        ],
      ),
    );
  }

  /// Taller than the app's compact default: these three are the screen's
  /// primary controls, and nothing below them works until they are set.
  static const double _fieldHeight = 46;

  Widget _field({
    required String label,
    required Widget child,
    bool required = false,
    String? hint,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            if (required)
              Text(' *',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary)),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = _current;

    if (_primary == null) {
      return _placeholder(
        Icons.alt_route_outlined,
        'Pick a branch to begin',
        'Your electives depend on it. The choice carries across all three tabs.',
      );
    }
    if (state.loading) return const CourseListSkeleton();

    if (state.courses.isEmpty) {
      return _placeholder(
        _pool.icon,
        'No ${_pool.short} courses',
        state.error.isEmpty ? _pool.blurb : state.error,
      );
    }

    final results = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // What this pool actually is. The old Open Electives screen
              // explained itself above the selectors; that note is the only
              // place the DEL/HUEL-counts-as-OPEL rule is written down.
              _poolNote(context),
              _clashToggle(context),
              AppSearchField(
                controller: _search,
                hint: 'Search ${_pool.short} by code or name…',
                onChanged: (v) => setState(() => state.query = v.trim()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    state.query.isEmpty
                        ? '${results.length} ${_pool.short} course'
                            '${results.length == 1 ? '' : 's'}'
                        : '${results.length} matching "${state.query}"',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (state.unavailable > 0) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '· ${state.unavailable} not offered this semester',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: results.isEmpty
              ? _placeholder(
                  Icons.search_off,
                  'Nothing matches "${state.query}"',
                  'Try a course code, or clear the search.',
                )
              : ElectiveCourseList(
                  courses: results,
                  catalog: _catalog,
                  selectionLink: widget.selectionLink,
                ),
        ),
      ],
    );
  }

  /// Standing explanation of the open pool. Shown for every pool, but it is
  /// Open Electives that genuinely needs it.
  Widget _poolNote(BuildContext context) {
    if (_pool != ElectivePool.open) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pool.blurb,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Spells out what is actually being compared, which depends on what is
  /// known: the CDCs for the chosen branch and semester, the open timetable,
  /// both, or — before a branch is picked — neither.
  String get _hidingLabel {
    final hasTimetable =
        (widget.selectionLink?.selectedSections ?? const []).isNotEmpty;
    final hasCores = _coreCourses.isNotEmpty;
    if (hasCores && hasTimetable) {
      return 'Hiding clashes with your core courses and your timetable';
    }
    if (hasCores) return 'Hiding clashes with your core courses';
    if (hasTimetable) return 'Hiding clashes with your timetable';
    return 'Nothing to clash against yet';
  }

  /// Lets the student see the electives that were being filtered out.
  Widget _clashToggle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 15, color: scheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _hideCoreClashes ? _hidingLabel : 'Showing every course, clashes included',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Switch(
            value: _hideCoreClashes,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              // Pure client-side filter now, so nothing needs refetching.
              setState(() => _hideCoreClashes = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _placeholder(IconData icon, String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      // Scrollable: at 320 px the blurb wraps far enough that a fixed Column
      // overflowed the viewport by ~150 px.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Electives',
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            for (final p in ElectivePool.values)
              Tab(icon: Icon(p.icon, size: 18), text: p.label),
          ],
        ),
      ),
      body: _loading
          ? const CourseListSkeleton()
          : Column(
              children: [
                if (_loadError.isNotEmpty)
                  InlineErrorCard(message: _loadError),
                _buildHeader(context),
                Expanded(child: _buildBody(context)),
              ],
            ),
    );
  }
}
