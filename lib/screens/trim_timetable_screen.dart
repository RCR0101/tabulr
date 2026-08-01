import 'package:flutter/material.dart';
import '../models/timetable.dart' as tt;
import '../models/timetable_constraints.dart';
import '../models/timetable_selection_link.dart';
import '../services/core/timetable_generator_controller.dart';
import '../services/core/timetable_service.dart';
import '../services/core/timetable_trimmer.dart';
import '../services/data/campus_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/carousel_pager.dart';
import '../widgets/generator/constraints_panel.dart';
import '../widgets/generator/ranking_importance_panel.dart';
import '../widgets/sample_timetable_card.dart';

/// Cuts an overloaded timetable down to ones that actually work.
///
/// A student with clash bypass on ends up with a wishlist rather than a
/// timetable, and the decision left to them — which courses to give up — is
/// the hard part. This runs the generator over their own selection and ranks
/// the survivors, so the choice is between named trade-offs instead of trial
/// and error on the grid.
class TrimTimetableScreen extends StatefulWidget {
  const TrimTimetableScreen({super.key, this.link});

  /// The timetable being trimmed. Null means none is open, which leaves the
  /// screen with nothing to work on — a trim is defined entirely by the
  /// selection it starts from.
  final TimetableSelectionLink? link;

  @override
  State<TrimTimetableScreen> createState() => _TrimTimetableScreenState();
}

class _TrimTimetableScreenState extends State<TrimTimetableScreen> {
  TrimResult? _result;
  bool _running = true;
  String? _error;

  /// Courses the student will not give up. Empty to begin with: the point is
  /// to be shown the options first, and pin only once one of them is wrong.
  final Set<String> _pinned = {};

  /// Null means "as many as fit", which is the honest default — the student
  /// came here because they do not know the number.
  int? _keepAtMost;

  /// Holds the tuning — gaps, free days, time of day, exam slots, and the axis
  /// weights. The generator's own controller rather than a parallel set of
  /// fields, so the preference panel and the ranker behave identically here and
  /// on the generator screen.
  final _prefs = TimetableGeneratorController();

  /// Whether the tuning panel is open. Closed to begin with: the ranked options
  /// are the answer most students want, and the knobs are for when that answer
  /// is not the one they wanted.
  bool _tuning = false;

  final _pageController = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _prefs.dispose();
    super.dispose();
  }

  /// The link's live selection as a timetable the trimmer can read. Rebuilt per
  /// run rather than held, so a change made behind this screen is picked up.
  tt.Timetable? get _source {
    final link = widget.link;
    if (link == null) return null;
    return tt.Timetable(
      id: 'trim',
      name: link.timetableName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      campus: CampusService.currentCampus,
      availableCourses: link.availableCourses,
      selectedSections: List.of(link.selectedSections),
      clashWarnings: const [],
      creditBasis: link.creditBasis,
    );
  }

  Future<void> _run() async {
    final source = _source;
    if (source == null) {
      setState(() => _running = false);
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await TimetableTrimmer.trim(
        source,
        pinned: _pinned,
        keepAtMost: _keepAtMost,
        preferences: _prefs.buildConstraints(),
        importance: _prefs.axisImportance,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
        _page = 0;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int get _courseCount => _result?.considered.length ?? 0;

  /// How many knobs the student has actually moved, so the header can say
  /// whether these options reflect their preferences or the defaults.
  int get _tunedCount {
    final c = _prefs.buildConstraints();
    final d = TimetableConstraints();
    var n = _prefs.axisImportance.length;
    if (c.minimizeGaps != d.minimizeGaps) n++;
    if (c.avoidBackToBackClasses != d.avoidBackToBackClasses) n++;
    if (c.protectLunchBreak != d.protectLunchBreak) n++;
    if (c.timeOfDayPreference != d.timeOfDayPreference) n++;
    if (c.maxHoursPerDay != d.maxHoursPerDay) n++;
    if (c.earliestStartSlot != null || c.latestEndSlot != null) n++;
    if (c.freeDayPreference.isNotEmpty) n++;
    if (c.avoidTimes.isNotEmpty) n++;
    if (c.avoidLabs.isNotEmpty) n++;
    if (c.preferredMidsemSlot != null) n++;
    if (c.preferredCompreSlot != null) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.content_cut,
          title: 'Trim to fit',
          subtitle: 'Which courses to keep',
        ),
      ),
      body: Column(
        children: [
          _controls(),
          if (_tuning) Expanded(child: _tuningPanel()) else Expanded(child: _results()),
        ],
      ),
    );
  }

  /// The same preferences the generator screen offers, over this timetable's
  /// own courses. Instructor controls are left out: they key off the mandatory
  /// list, which here is only whatever the student pinned.
  Widget _tuningPanel() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [_prefs.constraints, _prefs.importance]),
              builder: (context, _) => Column(
                children: [
                  ConstraintsPanel(
                    controller: _prefs,
                    availableCourses: widget.link?.availableCourses ?? const [],
                    showInstructors: false,
                    title: 'What matters to you',
                  ),
                  const SizedBox(height: AppDesign.spacingMd),
                  RankingImportancePanel(
                    importance: _prefs.axisImportance,
                    onChanged: _prefs.setAxisImportance,
                    onReset: _prefs.clearAxisImportance,
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  setState(() => _tuning = false);
                  _run();
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply and re-rank'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    final scheme = Theme.of(context).colorScheme;
    final considered = _result?.considered ?? const <String>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keep at most',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface
                        .withValues(alpha: AppDesign.opacityMedium),
                  ),
                ),
              ),
              _keepChip(null, 'As many as fit'),
              for (var n = 2; n <= 6 && n < _courseCount; n++)
                _keepChip(n, '$n'),
            ],
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Row(
            children: [
              Expanded(
                child: Text(
                  _tunedCount == 0
                      ? 'Ranked on gaps, exam spacing and week shape'
                      : '$_tunedCount preference${_tunedCount == 1 ? '' : 's'} set',
                  style: TextStyle(
                    fontSize: 12,
                    color: _tunedCount == 0
                        ? scheme.onSurface
                            .withValues(alpha: AppDesign.opacityMedium)
                        : scheme.primary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    _running ? null : () => setState(() => _tuning = !_tuning),
                icon: Icon(_tuning ? Icons.close : Icons.tune, size: 16),
                label: Text(_tuning ? 'Close' : 'Tune'),
              ),
            ],
          ),
          if (considered.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Text(
              _pinned.isEmpty
                  ? 'Tap a course to keep it in every option'
                  : '${_pinned.length} pinned',
              style: TextStyle(
                fontSize: 12,
                color:
                    scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
              ),
            ),
            const SizedBox(height: AppDesign.spacingXs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in considered)
                  FilterChip(
                    label: Text(code, style: const TextStyle(fontSize: 11)),
                    selected: _pinned.contains(code),
                    avatar: _pinned.contains(code)
                        ? const Icon(Icons.push_pin, size: 13)
                        : null,
                    onSelected: _running
                        ? null
                        : (on) {
                            setState(() {
                              if (on) {
                                _pinned.add(code);
                              } else {
                                _pinned.remove(code);
                              }
                            });
                            _run();
                          },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _keepChip(int? value, String label) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: _keepAtMost == value,
          onSelected: _running
              ? null
              : (_) {
                  setState(() => _keepAtMost = value);
                  _run();
                },
        ),
      );

  Widget _results() {
    if (_running) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) return _explain(Icons.error_outline, error, isError: true);

    final link = widget.link;
    if (link == null) {
      return _explain(
        Icons.inbox_outlined,
        'Open this from a timetable. Trimming works on a selection you have '
        'already made — build the week you want, clashes and all, then come '
        'back here to find out what fits.',
      );
    }
    if (link.selectedSections.isEmpty) {
      return _explain(
        Icons.inbox_outlined,
        'This timetable is empty, so there is nothing to trim. Add the courses '
        'you want — clashes and all — and come back.',
      );
    }

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    if (result.options.isEmpty) {
      // A required preference the student set themselves is the likeliest
      // reason nothing came back, and the fix is theirs to make — so name the
      // rule rather than reporting a dead end.
      if (result.unmetIntents.isNotEmpty) {
        return _explain(
          Icons.rule,
          'No combination of these courses satisfies every rule you marked as '
          'required:\n\n${result.unmetIntents.join('\n')}\n\n'
          'Relax one in Tune and try again.',
          isError: true,
        );
      }
      final impossible = result.impossible;
      return _explain(
        Icons.warning_amber,
        impossible.isNotEmpty
            ? '${impossible.first} and ${impossible.last} clash in every '
                'combination of their sections, so no timetable can keep both. '
                'Unpin one of them.'
            : _pinned.isEmpty
                ? 'None of these ${result.considered.length} courses could be '
                    'placed at all — they may have no sections in this '
                    'catalogue.'
                : 'The ${_pinned.length} pinned courses cannot sit together. '
                    'Unpin one and try again.',
        isError: true,
      );
    }

    final options = result.options;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: options.length,
            itemBuilder: (context, i) => _optionCard(options[i], result),
          ),
        ),
        _pager(options.length),
      ],
    );
  }

  Widget _optionCard(TrimOption option, TrimResult result) {
    final sections = TimetableTrimmer.sectionsOf(option);
    return SampleTimetableCard(
      generated: option.timetable,
      slots: TimetableService().generateTimetableSlots(
        sections,
        widget.link?.availableCourses ?? const [],
        campus: CampusService.currentCampus,
      ),
      title: 'Keeps ${option.kept.length} of ${result.considered.length}',
      // The dropped list is the decision, so it is the subtitle when short and
      // the chip strip regardless — a student compares options by what each
      // one costs them.
      subtitle: option.dropped.isEmpty
          ? 'Everything fits — nothing to give up'
          : 'Gives up ${option.dropped.length}',
      chips: option.dropped,
      chipsAreLosses: true,
      useLabel: 'Keep these',
      onUse: () => _confirm(option, sections),
    );
  }

  void _confirm(TrimOption option, List<tt.SelectedSection> sections) {
    final link = widget.link;
    AppDialog.adaptive(
      context: context,
      title: option.dropped.isEmpty ? 'Apply this timetable' : 'Drop these courses?',
      icon: Icons.content_cut,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (option.dropped.isNotEmpty) ...[
            const Text('Removed from this timetable:',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            for (final code in option.dropped)
              Text('• $code', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
          ],
          Text('Keeping ${option.kept.join(', ')}',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
        AppButton(
          label: 'Apply',
          onTap: () {
            Navigator.pop(context);
            if (link != null) _apply(link, option, sections);
          },
        ),
      ],
    );
  }

  /// Writes the option back through the editor's own toggle.
  ///
  /// Removals go first: the sections being kept may be different sections of
  /// courses already on the grid, and adding one of those while the old one is
  /// still there is a switch the editor would have to untangle. Going through
  /// the link rather than replacing the list wholesale means the editor rebuilds
  /// its clash warnings and records undo entries exactly as it would for a
  /// manual edit.
  void _apply(
    TimetableSelectionLink link,
    TrimOption option,
    List<tt.SelectedSection> sections,
  ) {
    final wanted = {for (final s in sections) '${s.courseCode}|${s.sectionId}'};
    for (final existing in List.of(link.selectedSections)) {
      if (wanted.contains('${existing.courseCode}|${existing.sectionId}')) continue;
      link.onSectionToggle(existing.courseCode, existing.sectionId, true);
    }
    final present = {
      for (final s in link.selectedSections) '${s.courseCode}|${s.sectionId}',
    };
    for (final section in sections) {
      if (present.contains('${section.courseCode}|${section.sectionId}')) continue;
      link.onSectionToggle(section.courseCode, section.sectionId, false);
    }
    ToastService.showSuccess(option.dropped.isEmpty
        ? 'Applied — nothing had to be dropped'
        : 'Kept ${option.kept.length}, dropped ${option.dropped.join(', ')}');
    if (mounted) Navigator.pop(context);
  }

  Widget _pager(int count) => CarouselPager(
        page: _page,
        count: count,
        onGoTo: _goTo,
      );

  void _goTo(int page) => _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  Widget _explain(IconData icon, String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: color, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
