import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/course.dart';
import '../models/timetable.dart' as tt;
import '../models/timetable_selection_link.dart';
import '../services/core/sample_timetable_service.dart';
import '../services/core/timetable_ranker.dart';
import '../services/core/timetable_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_data_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/branch_constants.dart' as branch_constants;
import '../utils/design_constants.dart';
import '../widgets/auto_load_cdc_dialog.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/carousel_pager.dart';
import '../widgets/error_dialog.dart';
import '../widgets/sample_timetable_card.dart';
import '../utils/page_info_helper.dart';

/// Ready-made timetables for a branch's core package.
///
/// The generator can already produce these, but only after a student knows it
/// exists, finds Auto-add CDCs and presses Generate. This screen is that
/// sequence in one step, for the semester they pick.
class SampleTimetablesScreen extends StatefulWidget {
  const SampleTimetablesScreen({
    super.key,
    this.selectionLink,
    this.courseLoader,
    this.initialPick,
    this.sampleBuilder,
  });

  /// Non-null when opened from inside the editor, in which case a sample can be
  /// added straight to the timetable being edited.
  final TimetableSelectionLink? selectionLink;

  /// Lets previews render the setup state without starting remote data access.
  final Future<List<Course>> Function()? courseLoader;

  final AutoLoadCDCResult? initialPick;
  final Future<SampleTimetables> Function(
    AutoLoadCDCResult pick,
    List<Course> courses,
  )?
  sampleBuilder;

  @override
  State<SampleTimetablesScreen> createState() => _SampleTimetablesScreenState();
}

class _SampleTimetablesScreenState extends State<SampleTimetablesScreen> {
  List<Course> _courses = [];
  SampleTimetables? _result;
  AutoLoadCDCResult? _picked;

  bool _loading = true;
  bool _generating = false;

  /// The generator's own refusal, when it threw one — an exam clash names the
  /// two courses and the slot they share, which is the whole answer.
  String? _error;

  final _pageController = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPick;
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final courses =
          await (widget.courseLoader?.call() ??
              CourseDataService().fetchCourses());
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
      });
      final initial = _picked;
      if (initial != null) await _generate(initial);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ErrorDialog.show(context, 'Error loading courses: $e');
    }
  }

  Future<void> _changePick() async {
    final result = await showDialog<AutoLoadCDCResult>(
      context: context,
      builder:
          (_) => AutoLoadCDCDialog(
            // Only the first semester of each year has a package published to
            // build a sample from.
            semesters: SemesterConstants.firstSemesters,
            initialValue: _picked,
          ),
    );
    if (result == null || !mounted) return;
    setState(() => _picked = result);
    await _generate(result);
  }

  Future<void> _selectInitial(AutoLoadCDCResult result) async {
    setState(() => _picked = result);
    await _generate(result);
  }

  Future<void> _generate(AutoLoadCDCResult pick) async {
    setState(() {
      _generating = true;
      _result = null;
      _error = null;
      _page = 0;
    });
    try {
      final customBuilder = widget.sampleBuilder;
      final result =
          customBuilder != null
              ? await customBuilder(pick, _courses)
              : await SampleTimetableService.build(
                primaryBranch: pick.primaryBranch,
                secondaryBranch: pick.secondaryBranch,
                semester: pick.semester,
                availableCourses: _courses,
                chosen: pick.chosen,
              );
      if (!mounted) return;
      setState(() {
        _result = result;
        _generating = false;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<tt.SelectedSection> _sectionsOf(RankedTimetable ranked) => [
    for (final s in ranked.timetable.sections)
      tt.SelectedSection(
        courseCode: s.courseCode,
        sectionId: s.sectionId,
        section: s.section,
      ),
  ];

  String _nameFor(RankedTimetable ranked) {
    final pick = _picked;
    return pick == null
        ? 'Sample timetable'
        : 'Sample ${pick.semester} · ${pick.primaryBranch}';
  }

  void _offerActions(RankedTimetable ranked) {
    final sections = _sectionsOf(ranked);
    final link = widget.selectionLink;

    AppDialog.adaptive(
      context: context,
      title: 'Use this sample',
      icon: Icons.calendar_view_week,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in sections)
            Text(
              '• ${s.courseCode} — ${s.sectionId}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
        if (link == null)
          AppButton(
            label: 'Overwrite…',
            variant: AppButtonVariant.secondary,
            onTap: () {
              Navigator.pop(context);
              _overwrite(sections);
            },
          ),
        AppButton(
          label: 'Save as new',
          variant:
              link == null
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
          onTap: () {
            Navigator.pop(context);
            _saveAsNew(sections, _nameFor(ranked));
          },
        ),
        if (link != null)
          AppButton(
            label: 'Add to this timetable',
            onTap: () {
              Navigator.pop(context);
              _addToOpenTimetable(link, sections);
            },
          ),
      ],
    );
  }

  /// Adds through the editor's own add, one section at a time, so a section
  /// that clashes with something already there is refused and explained rather
  /// than silently overwriting the student's work.
  void _addToOpenTimetable(
    TimetableSelectionLink link,
    List<tt.SelectedSection> sections,
  ) {
    final already = {
      for (final s in link.selectedSections) '${s.courseCode}|${s.sectionId}',
    };
    var added = 0;
    for (final section in sections) {
      if (already.contains('${section.courseCode}|${section.sectionId}')) {
        continue;
      }
      link.onSectionToggle(section.courseCode, section.sectionId, false);
      added++;
    }
    if (added == 0) {
      ToastService.showInfo('Every section of this sample is already on it');
    }
  }

  Future<void> _saveAsNew(
    List<tt.SelectedSection> sections,
    String name,
  ) async {
    try {
      await SampleTimetableService.saveAsNew(
        sections,
        name,
        basis: _result?.basis ?? CreditBasis.units,
      );
      if (!mounted) return;
      ToastService.showSuccess('Saved as "$name"');
    } catch (e) {
      if (mounted) ErrorDialog.show(context, 'Could not save: $e');
    }
  }

  Future<void> _overwrite(List<tt.SelectedSection> sections) async {
    final timetables = await TimetableService().getAllTimetables();
    if (!mounted) return;
    if (timetables.isEmpty) {
      ToastService.showInfo('You have no timetables to overwrite yet');
      return;
    }

    final target = await showDialog<tt.Timetable>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Overwrite which timetable?'),
            content: SizedBox(
              width: 360,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in timetables)
                    ListTile(
                      title: Text(t.name),
                      subtitle: Text('${t.selectedSections.length} sections'),
                      onTap: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
    if (target == null || !mounted) return;

    // Destructive and not undoable from here — the sections it drops are gone
    // once saved, so it is asked for plainly rather than assumed.
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Replace "${target.name}"?'),
            content: Text(
              'Its ${target.selectedSections.length} section'
              '${target.selectedSections.length == 1 ? '' : 's'} will be replaced '
              'by this sample.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await SampleTimetableService.overwrite(
        target,
        sections,
        _courses,
        basis: _result?.basis ?? CreditBasis.units,
      );
      if (!mounted) return;
      ToastService.showSuccess('Replaced "${target.name}"');
    } catch (e) {
      if (mounted) ErrorDialog.show(context, 'Could not overwrite: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pick = _picked;
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Sample Timetables',
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.sampleTimetables),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : pick == null
              ? _setup()
              : Column(
                children: [_pickHeader(pick), Expanded(child: _results())],
              ),
    );
  }

  Widget _pickHeader(AutoLoadCDCResult pick) {
    final scheme = Theme.of(context).colorScheme;
    final name = branch_constants.branchLabel(pick.primaryBranch);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'Semester ${pick.semester}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(
                      alpha: AppDesign.opacityMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _generating ? null : _changePick,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _setup() {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesign.spacingLg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Container(
            padding: const EdgeInsets.all(AppDesign.spacingLg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.44),
                  scheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.06),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start with your core package',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose your branch and semester once. Tabulr will build and rank clash-free sample timetables from the published CDCs.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                AutoLoadCDCSelector(
                  semesters: SemesterConstants.firstSemesters,
                  actionLabel: 'Generate samples',
                  onSelected: _selectInitial,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results() {
    if (_generating) {
      return const Center(child: CircularProgressIndicator());
    }

    // The generator threw: an exam clash, or a course missing from the
    // catalog. Its own sentence names the courses, so it is shown as written.
    final error = _error;
    if (error != null) {
      return _explain(Icons.error_outline, error, isError: true);
    }

    final result = _result;
    if (result == null) {
      return const SizedBox.shrink();
    }

    // Three different answers, which used to be one empty list.
    if (!result.hasPackage) {
      final pick = _picked!;
      return _explain(
        Icons.inbox_outlined,
        'No core courses are published for '
        '${branch_constants.branchLabel(pick.primaryBranch)} in '
        '${pick.semester} on this campus, so there is nothing to build a '
        'sample from.',
      );
    }
    if (result.samples.isEmpty) {
      final blocking = result.blocking;
      return _explain(
        Icons.warning_amber,
        blocking == null
            ? 'The ${result.codes.length} core courses for this semester cannot '
                'all fit in one week — no clash-free arrangement of their '
                'sections exists.\n\n${result.codes.join(', ')}'
            : '${blocking.$1} and ${blocking.$2} clash in every combination of '
                'their sections, so no timetable can hold both.\n\nThis is the '
                'published package, not a limit of the generator — worth '
                'raising with your department.',
        isError: true,
      );
    }

    final samples = result.samples;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: samples.length,
            itemBuilder: (context, i) => _sampleCard(samples[i]),
          ),
        ),
        _pager(samples.length),
      ],
    );
  }

  Widget _sampleCard(RankedTimetable ranked) => SampleTimetableCard(
    generated: ranked.timetable,
    slots: TimetableService().generateTimetableSlots(
      _sectionsOf(ranked),
      _courses,
      campus: CampusService.currentCampus,
    ),
    onUse: () => _offerActions(ranked),
  );

  /// Swipe position. The cards scroll horizontally, so there is nothing on
  /// screen to say how many there are or where you are in them.
  Widget _pager(int count) =>
      CarouselPager(page: _page, count: count, onGoTo: _goTo);

  void _goTo(int page) => _pageController.animateToPage(
    page,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  Widget _explain(IconData icon, String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        isError
            ? scheme.error
            : scheme.onSurface.withValues(alpha: AppDesign.opacityMedium);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(
              label: 'Pick another semester',
              variant: AppButtonVariant.secondary,
              onTap: _changePick,
            ),
          ],
        ),
      ),
    );
  }
}
