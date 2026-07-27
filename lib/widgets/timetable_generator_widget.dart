import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/course.dart';
import '../utils/datetime_utils.dart';
import 'common/app_tappable.dart';
import '../models/timetable_constraints.dart';
import '../services/core/timetable_generator_controller.dart';
import '../services/core/timetable_ranker.dart';
import '../services/core/clash_detector.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/auto_load_cdc_service.dart';
import '../services/data/academic_record_service.dart';
import '../repositories/prerequisites_repository.dart';
import '../models/academic_record.dart';
import '../models/prerequisite.dart';
import '../models/prerequisite_status.dart';
import 'auto_load_cdc_dialog.dart';
import '../models/timetable.dart' as tt_model;
import '../screens/timetable_comparison_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/design_constants.dart';
import 'common/app_dialog.dart';
import 'common/app_dropdown.dart';
import 'common/app_button.dart';
import 'generated_timetable_card.dart';
import 'generator/time_avoidance_dialog.dart';
import 'generator/lab_avoidance_dialog.dart';
import 'generator/instructor_avoidance_dialog.dart';
import 'generator/instructor_ranking_dialog.dart';
import 'generator/constraint_controls.dart';
import 'generator/generator_results_views.dart';
import 'generator/ranking_importance_panel.dart';

class TimetableGeneratorWidget extends StatefulWidget {
  final List<Course> availableCourses;
  final Function(GeneratedTimetable) onTimetableSelected;

  const TimetableGeneratorWidget({
    super.key,
    required this.availableCourses,
    required this.onTimetableSelected,
  });

  @override
  State<TimetableGeneratorWidget> createState() => _TimetableGeneratorWidgetState();
}

class _TimetableGeneratorWidgetState extends State<TimetableGeneratorWidget>
    with SingleTickerProviderStateMixin {
  final TimetableGeneratorController _ctrl = TimetableGeneratorController();
  final ValueNotifier<bool> _isAutoLoadingCDCs = ValueNotifier(false);

  /// Indices into `_ctrl.rankedTimetables` currently picked for comparison.
  /// A ValueNotifier rather than State: toggling a compare checkbox is a
  /// results-panel concern and must not repaint the configuration form.
  final ValueNotifier<Set<int>> _compareSelection = ValueNotifier(const {});
  TabController? _tabController;

  // Loaded once for the prereq warning: the student's cleared courses and the
  // prereq requirements keyed by course code. Both are best-effort — if either
  // is unavailable the warning simply stays quiet.
  AcademicRecord _record = AcademicRecord.empty;
  final Map<String, CoursePrerequisites> _prereqByCode = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPrereqData();
  }

  Future<void> _loadPrereqData() async {
    try {
      final record = await AcademicRecordService().load();
      // No CGPA record means every verdict is "unknown", so there's nothing to
      // warn about — skip the prereq fetch entirely.
      if (!record.isNotEmpty) return;
      final withPrereqs = await PrerequisitesRepository().getCoursesWithPrerequisites();
      if (!mounted) return;
      setState(() {
        _record = record;
        for (final c in withPrereqs) {
          _prereqByCode[c.courseCode] = c;
        }
      });
    } catch (_) {
      // Prereq warnings are advisory; a load failure must not break generation.
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _compareSelection.dispose();
    _isAutoLoadingCDCs.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  /// Subscribes a panel to one slice of the controller.
  ///
  /// Replaces the single `setState(() {})` this widget used to run on every
  /// notification, which rebuilt the whole 2.6k-line tree — both config panels,
  /// the importance grid, the generate button AND the results list — whenever
  /// one checkbox moved. Slices keep a constraint edit out of the course
  /// search's typeahead and out of the results list entirely.
  Widget _watch(Listenable slice, Widget Function() build) =>
      ListenableBuilder(listenable: slice, builder: (_, __) => build());

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);

    if (isMobile) {
      return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.settings), text: 'Configure'),
                  Tab(icon: Icon(Icons.view_list), text: 'Results'),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Configuration Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                _watch(_ctrl.courses, _buildConfigurationPanel),
                                const SizedBox(height: 16),
                                _watch(_ctrl.constraints, _buildConstraintsPanel),
                                const SizedBox(height: 16),
                                _watch(
                          _ctrl.importance,
                          () => RankingImportancePanel(
                            importance: _ctrl.axisImportance,
                            onChanged: _ctrl.setAxisImportance,
                            onReset: _ctrl.clearAxisImportance,
                          ),
                        ),
                              ],
                            ),
                          ),
                        ),
                        _watch(
                          Listenable.merge([_ctrl.courses, _ctrl.results]),
                          () => GenerateButton(
                            enabled: _ctrl.mandatoryCourses.isNotEmpty,
                            isGenerating: _ctrl.isGenerating,
                            onGenerate: _generateTimetables,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Results Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _watch(_ctrl.results, _buildResultsPanel),
                  ),
                ],
              ),
            ),
          ],
        );
    }

    // Desktop layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel - Configuration
        Expanded(
          flex: 1,
          child: Column(
            children: [
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      _watch(_ctrl.courses, _buildConfigurationPanel),
                      const SizedBox(height: 16),
                      _watch(_ctrl.constraints, _buildConstraintsPanel),
                      const SizedBox(height: 16),
                      _watch(
                          _ctrl.importance,
                          () => RankingImportancePanel(
                            importance: _ctrl.axisImportance,
                            onChanged: _ctrl.setAxisImportance,
                            onReset: _ctrl.clearAxisImportance,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _watch(
                          Listenable.merge([_ctrl.courses, _ctrl.results]),
                          () => GenerateButton(
                            enabled: _ctrl.mandatoryCourses.isNotEmpty,
                            isGenerating: _ctrl.isGenerating,
                            onGenerate: _generateTimetables,
                          ),
                        ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right panel - Results
        Expanded(
          flex: 2,
          child: _watch(_ctrl.results, _buildResultsPanel),
        ),
      ],
    );
  }

  Widget _buildConfigurationPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Course Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCourseSelection(),
                _buildPrereqWarning(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConstraintsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      // The panel's card colour would otherwise hide the ink/background of the
      // CheckboxListTiles inside it. A transparent Material puts those effects
      // back on top of the card, clipped to the same corners.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Constraints & Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildConstraints(),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.view_list,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Generated Timetables',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_ctrl.rankedTimetables.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_ctrl.rankedTimetables.length} found',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Results appear after a visibly slow generate, and previously
          // replaced the empty state in one hard cut. The keys are what make
          // the switcher fire: without them the two branches are both a
          // Widget subtree at the same position and it cross-fades nothing.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              child: _ctrl.rankedTimetables.isEmpty
                  ? KeyedSubtree(
                      key: const ValueKey('results-empty'),
                      child: EmptyResults(
                        isGenerating: _ctrl.isGenerating,
                        result: _ctrl.rankingResult,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('results-list'),
                      child: _buildGeneratedTimetables(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pulls the CDCs for the student's degree+year (via the shared dialog) and
  /// drops the course codes straight into the mandatory list — the generator
  /// picks the actual sections. Codes already sitting in the optional list are
  /// promoted to mandatory rather than duplicated.
  Future<void> _autoAddCDCs() async {
    final result = await showDialog<AutoLoadCDCResult>(
      context: context,
      builder: (context) => const AutoLoadCDCDialog(),
    );
    if (result == null || !mounted) return;

    _isAutoLoadingCDCs.value = true;
    try {
      final sections = await AutoLoadCDCService().loadCDCsForDegree(
        primaryBranch: result.primaryBranch,
        secondaryBranch: result.secondaryBranch,
        semester: result.semester,
        availableCourses: widget.availableCourses,
        chosen: result.chosen,
      );
      if (!mounted) return;

      final codes = sections.map((s) => s.courseCode).toSet();
      final added = _ctrl.addMandatoryCourses(codes);

      if (added > 0) {
        ToastService.showSuccess('Added $added CDC${added > 1 ? 's' : ''} to mandatory courses');
      } else if (codes.isNotEmpty) {
        ToastService.showInfo('All CDCs for that branch and year are already added');
      } else {
        ToastService.showInfo('No CDC courses found for the selected branch and year');
      }
    } catch (e) {
      if (mounted) ToastService.showError('Could not auto-add CDCs: $e');
    } finally {
      if (mounted) _isAutoLoadingCDCs.value = false;
    }
  }

  Widget _buildCourseSelection() {
    final mandatoryCredits = _ctrl.mandatoryCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });
    final optionalCredits = _ctrl.optionalCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Mandatory Courses (${mandatoryCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isAutoLoadingCDCs,
              builder: (context, loading, _) => TextButton.icon(
                onPressed: loading ? null : _autoAddCDCs,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('Auto-add CDCs'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Must be included in every timetable', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(
          targetList: _ctrl.mandatoryCourses,
          otherList: _ctrl.optionalCourses,
          onPick: _ctrl.addMandatoryCourse,
        ),
        const SizedBox(height: 8),
        _buildCourseBadges(
          _ctrl.mandatoryCourses,
          isMandatory: true,
          onRemove: _ctrl.removeMandatoryCourse,
        ),
        const SizedBox(height: 16),
        Text('Optional Courses (${optionalCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Generator will fit as many as possible within credit limit', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(
          targetList: _ctrl.optionalCourses,
          otherList: _ctrl.mandatoryCourses,
          onPick: _ctrl.addOptionalCourse,
        ),
        _buildOptionalTargetSelector(),
        const SizedBox(height: 8),
        _buildOptionalCoursesRanking(),
      ],
    );
  }

  /// "Any N of M electives" — cap how many optionals the generator includes.
  /// Only meaningful once there are at least two optionals to choose between.
  Widget _buildOptionalTargetSelector() {
    final m = _ctrl.optionalCourses.length;
    if (m < 2) return const SizedBox.shrink();

    // The controller clamps a stale target (optionals removed) on read, so this
    // no longer writes to it mid-build.
    final target = _ctrl.optionalTarget;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              target == null ? 'Include: as many as fit' : 'Include: any $target of $m',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Fewer',
            onPressed: () {
              // as-many (null) → one below M, then down to 1, no lower.
              final current = _ctrl.optionalTarget ?? m;
              _ctrl.optionalTarget = (current - 1).clamp(1, m);
            },
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          Text(
            target?.toString() ?? 'All',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'More',
            onPressed: () {
              // Stepping up past M-1 means "all", represented as null.
              final current = _ctrl.optionalTarget ?? m;
              final next = current + 1;
              _ctrl.optionalTarget = next >= m ? null : next;
            },
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
        ],
      ),
    );
  }

  /// Advisory banner: for each selected course whose `pre` requirements the
  /// student's record shows as not-yet-cleared, list what's still missing.
  /// Never blocks generation — some students clear things off-record.
  Widget _buildPrereqWarning() {
    if (_prereqByCode.isEmpty) return const SizedBox.shrink();

    final warnings = <String, List<String>>{};
    for (final code in [..._ctrl.mandatoryCourses, ..._ctrl.optionalCourses]) {
      final prereqs = _prereqByCode[code];
      if (prereqs == null) continue;
      final status = PrerequisiteStatus.of(prereqs, _record);
      if (status.isMet == false) {
        warnings[code] = status.outstanding.map((g) => g.label).toList();
      }
    }

    if (warnings.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppDesign.warning(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppDesign.warning(context).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule, size: 18, color: AppDesign.warning(context)),
                const SizedBox(width: 6),
                Text(
                  'Prerequisite check',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppDesign.warning(context)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Your CGPA record doesn't show these as cleared yet:",
              style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 6),
            ...warnings.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.9)),
                  children: [
                    TextSpan(text: '${e.key} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                      text: e.value.isEmpty ? '— prerequisites not met' : '— needs ${e.value.join(", ")}',
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseSearchField({
    required List<String> targetList,
    required List<String> otherList,
    required ValueChanged<String> onPick,
  }) {
    return TypeAheadField<Course>(
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Search courses by code or name...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        );
      },
      suggestionsCallback: (pattern) {
        if (pattern.isEmpty) return <Course>[];

        return widget.availableCourses.where((course) {
          if (course.totalCredits == 0) return false;
          final searchLower = pattern.toLowerCase();
          return course.courseCode.toLowerCase().contains(searchLower) ||
                 course.courseTitle.toLowerCase().contains(searchLower);
        }).take(10).toList();
      },
      itemBuilder: (context, course) {
        final inTarget = targetList.contains(course.courseCode);
        final inOther = otherList.contains(course.courseCode);
        return ListTile(
          leading: Icon(
            inTarget || inOther ? Icons.check_circle : Icons.add_circle_outline,
            color: inTarget || inOther ? AppDesign.success(context) : AppDesign.info(context),
          ),
          title: Text(course.courseCode),
          subtitle: Text(
            course.courseTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${course.totalCredits} credits'),
        );
      },
      onSelected: (course) => onPick(course.courseCode),
      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No courses found'),
      ),
    );
  }

  Widget _buildCourseBadges(
    List<String> courseList, {
    required bool isMandatory,
    required ValueChanged<String> onRemove,
  }) {
    if (courseList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            isMandatory ? 'No mandatory courses' : 'No optional courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final badgeColor = isMandatory
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;

    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: courseList.map((courseCode) {
            final course = widget.availableCourses.firstWhere(
              (c) => c.courseCode == courseCode,
              orElse: () => Course(courseCode: courseCode, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
            );
            return Chip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.courseCode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: badgeColor)),
                  Text(
                    course.courseTitle,
                    style: TextStyle(fontSize: ResponsiveService.clampedFontSize(context, 9), color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => onRemove(courseCode),
              backgroundColor: badgeColor.withValues(alpha: 0.1),
              deleteIconColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: badgeColor.withValues(alpha: 0.3), width: 1),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<List<String>> _buildClashClusters(List<String> courseCodes) {
    final courses = <String, Course>{};
    for (final code in courseCodes) {
      courses[code] = widget.availableCourses.firstWhere(
        (c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
      );
    }

    final parent = <String, String>{};
    for (final code in courseCodes) {
      parent[code] = code;
    }
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }
    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < courseCodes.length; i++) {
      for (int j = i + 1; j < courseCodes.length; j++) {
        if (_coursesClash(courses[courseCodes[i]]!, courses[courseCodes[j]]!)) {
          union(courseCodes[i], courseCodes[j]);
        }
      }
    }

    final groups = <String, List<String>>{};
    for (final code in courseCodes) {
      final root = find(code);
      (groups[root] ??= []).add(code);
    }
    return groups.values.toList();
  }

  bool _coursesClash(Course a, Course b) {
    for (final secA in a.sections) {
      for (final secB in b.sections) {
        if (ClashDetector.sectionsConflict(secA, secB)) return true;
      }
    }
    if (a.midSemExam != null && b.midSemExam != null) {
      if (ClashDetector.examDatesConflict(a.midSemExam!, b.midSemExam!)) return true;
    }
    if (a.endSemExam != null && b.endSemExam != null) {
      if (ClashDetector.examDatesConflict(a.endSemExam!, b.endSemExam!)) return true;
    }
    return false;
  }

  Widget _buildOptionalCoursesRanking() {
    if (_ctrl.optionalCourses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            'No optional courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final clusters = _buildClashClusters(_ctrl.optionalCourses);
    final accentColor = Theme.of(context).colorScheme.tertiary;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int ci = 0; ci < clusters.length; ci++) ...[
          if (ci > 0) const SizedBox(height: 8),
          _buildClashCluster(clusters[ci], accentColor, scheme),
        ],
      ],
    );
  }

  Widget _buildClashCluster(List<String> clusterCodes, Color accentColor, ColorScheme scheme) {
    final isClashGroup = clusterCodes.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isClashGroup
              ? scheme.error.withValues(alpha: 0.3)
              : scheme.outline,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isClashGroup) ...[
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  'Timing conflict — drag to set priority',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: clusterCodes.length,
              onReorderItem: (oldIndex, newIndex) => _ctrl.moveOptionalCourse(
                clusterCodes[oldIndex],
                beforeCode: clusterCodes[newIndex],
              ),
              itemBuilder: (context, index) {
                return _buildOptionalCourseRow(
                  key: ValueKey(clusterCodes[index]),
                  courseCode: clusterCodes[index],
                  accentColor: accentColor,
                  draggable: true,
                  dragIndex: index,
                );
              },
            ),
          ] else
            _buildOptionalCourseRow(
              key: ValueKey(clusterCodes[0]),
              courseCode: clusterCodes[0],
              accentColor: accentColor,
              draggable: false,
            ),
        ],
      ),
    );
  }

  Widget _buildOptionalCourseRow({
    required Key key,
    required String courseCode,
    required Color accentColor,
    required bool draggable,
    int? dragIndex,
  }) {
    final course = widget.availableCourses.firstWhere(
      (c) => c.courseCode == courseCode,
      orElse: () => Course(courseCode: courseCode, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
    );
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (draggable)
            ReorderableDragStartListener(
              index: dragIndex!,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(Icons.drag_handle, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            )
          else
            const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(course.courseCode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: accentColor)),
                  Text(
                    course.courseTitle,
                    style: TextStyle(fontSize: ResponsiveService.clampedFontSize(context, 9), color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => _ctrl.removeOptionalCourse(courseCode),
            icon: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.error),
            tooltip: 'Remove $courseCode',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildConstraints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constraints & Preferences', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),

        // Schedule group
        ConstraintGroup(
          icon: Icons.schedule,
          title: 'Schedule',
          children: [
            ConstraintRow(
              label: 'Max hours/day',
              child: AppDropdown<int>(
                width: 80,
                value: _ctrl.maxHoursPerDay,
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}'),
                )),
                onChanged: (value) {
                  if (value != null) _ctrl.maxHoursPerDay = value;
                },
              ),
            ),
            _buildCheckConstraint('Avoid back-to-back classes', _ctrl.avoidBackToBack, (v) => _ctrl.avoidBackToBack = v ?? false),
            _buildCheckConstraint('Minimize gaps between classes', _ctrl.minimizeGaps, (v) => _ctrl.minimizeGaps = v ?? false),
            // Clearing lunch protection also drops requireLunchFree; that
            // cascade lives in the controller's setter.
            _buildCheckConstraint('Protect lunch break (12–2 PM)', _ctrl.protectLunchBreak, (v) => _ctrl.protectLunchBreak = v ?? false),
            if (_ctrl.protectLunchBreak)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: RequireToggle(
                  value: _ctrl.requireLunchFree,
                  onChanged: (v) => _ctrl.requireLunchFree = v,
                ),
              ),
            ConstraintRow(
              label: 'Prefer classes in',
              child: AppDropdown<TimeOfDayPreference>(
                value: _ctrl.timeOfDayPreference,
                items: const [
                  DropdownMenuItem(value: TimeOfDayPreference.none, child: Text('No preference')),
                  DropdownMenuItem(value: TimeOfDayPreference.morning, child: Text('Morning (before 12 PM)')),
                  DropdownMenuItem(value: TimeOfDayPreference.afternoon, child: Text('Afternoon (after 12 PM)')),
                ],
                onChanged: (value) => _ctrl.timeOfDayPreference = value ?? TimeOfDayPreference.none,
              ),
            ),
            const SizedBox(height: 8),
            _buildClassHoursWindow(),
            const SizedBox(height: 12),
            _buildFreeDayRanking(),
            const SizedBox(height: 12),
            _buildTimeAvoidance(),
            const SizedBox(height: 12),
            _buildLabAvoidance(),
          ],
        ),
        const SizedBox(height: 10),

        // Instructors group
        ConstraintGroup(
          icon: Icons.person,
          title: 'Instructors',
          children: [
            _buildInstructorAvoidance(),
            const SizedBox(height: 12),
            _buildInstructorRanking(),
          ],
        ),
        const SizedBox(height: 10),

        // Exams group
        ConstraintGroup(
          icon: Icons.event,
          title: 'Exams',
          children: [
            ConstraintRow(
              label: 'Preferred midsem',
              child: AppDropdown<TimeSlot?>(
                value: _ctrl.preferredMidsemSlot,
                hint: const Text('Any', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                  ...TimeSlotInfo.getMidSemSlots().map((slot) => DropdownMenuItem(
                    value: slot,
                    child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.campusId)),
                  )),
                ],
                onChanged: (value) => _ctrl.preferredMidsemSlot = value,
              ),
            ),
            ConstraintRow(
              label: 'Preferred compre',
              child: AppDropdown<TimeSlot?>(
                value: _ctrl.preferredCompreSlot,
                hint: const Text('Any', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                  ...TimeSlotInfo.getEndSemSlots().map((slot) => DropdownMenuItem(
                    value: slot,
                    child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.campusId)),
                  )),
                ],
                onChanged: (value) => _ctrl.preferredCompreSlot = value,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Short clock label for an hour slot (1 = 8 AM … 12 = 7 PM).
  String _slotClockLabel(int slot) {
    final hour24 = slot + 7; // slot 1 → 08:00
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 > 12 ? hour24 - 12 : hour24;
    return '$hour12 $period';
  }

  /// Soft "no classes before X / after Y" window. A full 1–12 range means no
  /// bound (nulls on the controller); narrowing either end sets that bound.
  Widget _buildClassHoursWindow() {
    final start = (_ctrl.earliestStartSlot ?? 1).toDouble();
    final end = (_ctrl.latestEndSlot ?? 12).toDouble();
    final isBounded = _ctrl.earliestStartSlot != null || _ctrl.latestEndSlot != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Class hours window', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(
              isBounded
                  ? '${_slotClockLabel(start.round())} – ${_slotClockLabel(end.round())}'
                  : 'Any time',
              style: TextStyle(
                fontSize: 12,
                color: isBounded ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isBounded)
              InkResponse(
                onTap: _ctrl.clearHoursWindow,
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
          ],
        ),
        RangeSlider(
          min: 1,
          max: 12,
          divisions: 11,
          values: RangeValues(start, end),
          labels: RangeLabels(_slotClockLabel(start.round()), _slotClockLabel(end.round())),
          onChanged: (values) => _ctrl.setHoursWindow(
            startSlot: values.start.round(),
            endSlot: values.end.round(),
          ),
        ),
        Text(
          'Classes outside this window are penalised, not blocked.',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
        ),
        if (isBounded)
          RequireToggle(
            value: _ctrl.requireHoursWindow,
            onChanged: (v) => _ctrl.requireHoursWindow = v,
          ),
      ],
    );
  }

  Widget _buildCheckConstraint(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onChanged: onChanged,
    );
  }

  Widget _buildFreeDayRanking() {
    final unranked = DayOfWeek.values
        .where((d) => !_ctrl.freeDayPreference.contains(d))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Free day preference:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              if (_ctrl.freeDayPreference.isNotEmpty)
                TextButton(
                  onPressed: _ctrl.clearFreeDayPreference,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap days in order of preference (most wanted free day first)',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          if (_ctrl.freeDayPreference.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _ctrl.freeDayPreference.length,
              onReorderItem: _ctrl.reorderFreeDayPreference,
              itemBuilder: (context, index) {
                final day = _ctrl.freeDayPreference[index];
                return Container(
                  key: ValueKey(day),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        getDayName(day, abbreviated: true),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _ctrl.removeFreeDayPreference(day),
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: 'Remove ${getDayName(day, abbreviated: true)}',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
          if (unranked.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unranked.map((day) {
                return ActionChip(
                  label: Text(getDayName(day, abbreviated: true), style: const TextStyle(fontSize: 12)),
                  onPressed: () => _ctrl.toggleFreeDayPreference(day),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          if (_ctrl.freeDayPreference.isNotEmpty)
            RequireToggle(
              value: _ctrl.requireFreeDays,
              onChanged: (v) => _ctrl.requireFreeDays = v,
            ),
        ],
      ),
    );
  }

  Widget _buildTimeAvoidance() {
    return ChipListSection(
      title: 'Avoid time slots:',
      actionLabel: 'Add',
      onAction: _addTimeAvoidance,
      chips: [
        for (final (index, a) in _ctrl.avoidTimes.indexed)
          RemovableChip(
            label: '${a.day.name}: ${_formatAvoidTimeHours(a.hours)}',
            onRemove: () => _ctrl.removeTimeAvoidance(index),
          ),
      ],
    );
  }

  Widget _buildLabAvoidance() {
    return ChipListSection(
      title: 'Avoid labs on:',
      actionLabel: 'Add',
      onAction: _addLabAvoidance,
      chips: [
        for (final (index, a) in _ctrl.avoidLabs.indexed)
          RemovableChip(
            label: '${a.day.name}: ${_formatAvoidTimeHours(a.hours)} (Labs)',
            onRemove: () => _ctrl.removeLabAvoidance(index),
            tint: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }

  Widget _buildInstructorAvoidance() {
    return ChipListSection(
      title: 'Avoid instructors:',
      actionLabel: 'Add',
      onAction: _ctrl.mandatoryCourses.isNotEmpty ? _addInstructorAvoidance : null,
      emptyHint: _ctrl.mandatoryCourses.isEmpty
          ? 'Select courses first to see available instructors'
          : null,
      chips: [
        for (final (index, name) in _ctrl.avoidedInstructors.indexed)
          RemovableChip(
            label: name,
            onRemove: () => _ctrl.removeAvoidedInstructor(index),
            tint: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }

  Widget _buildInstructorRanking() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Rank instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: _ctrl.mandatoryCourses.isNotEmpty ? _showInstructorRankingDialog : null,
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Rank', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_ctrl.instructorRankings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Current Rankings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_ctrl.instructorRankings.length} course${_ctrl.instructorRankings.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppTappable(
                      onTap: () => _ctrl.setInstructorRankings(const {}),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.clear_all,
                          size: 14,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ctrl.instructorRankings.entries.map((entry) {
                        final courseCode = entry.key;
                        final rankings = entry.value;
                        final totalRanked = rankings.lectureInstructors.length +
                                          rankings.practicalInstructors.length +
                                          rankings.tutorialInstructors.length;

                        return AppTappable(
                          onTap: () => _showInstructorRankingDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      courseCode,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        totalRanked.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (rankings.lectureInstructors.isNotEmpty)
                                      _buildSectionTypeBadge(context, 'L', rankings.lectureInstructors.length),
                                    if (rankings.practicalInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'P', rankings.practicalInstructors.length),
                                    ],
                                    if (rankings.tutorialInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'T', rankings.tutorialInstructors.length),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getTopInstructorSummary(rankings),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_ctrl.mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Text(
              'Select courses first to rank instructors',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTypeBadge(BuildContext context, String sectionType, int count) {
    final scheme = Theme.of(context).colorScheme;
    Color badgeColor;
    switch (sectionType) {
      case 'L':
        badgeColor = scheme.primary;
        break;
      case 'P':
        badgeColor = AppDesign.success(context);
        break;
      case 'T':
        badgeColor = AppDesign.warning(context);
        break;
      default:
        badgeColor = AppDesign.muted(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$sectionType:$count',
        style: TextStyle(
          fontSize: ResponsiveService.clampedFontSize(context, 9),
          fontWeight: FontWeight.bold,
          color: scheme.onPrimary,
        ),
      ),
    );
  }

  String _getTopInstructorSummary(InstructorRankings rankings) {
    final topInstructors = <String>[];

    if (rankings.lectureInstructors.isNotEmpty) {
      topInstructors.add('L: ${rankings.lectureInstructors.first}');
    }
    if (rankings.practicalInstructors.isNotEmpty) {
      topInstructors.add('P: ${rankings.practicalInstructors.first}');
    }
    if (rankings.tutorialInstructors.isNotEmpty) {
      topInstructors.add('T: ${rankings.tutorialInstructors.first}');
    }

    if (topInstructors.isEmpty) return 'No rankings set';
    return topInstructors.join(' • ');
  }

  String _formatAvoidTimeHours(List<int> hours) {
    if (hours.isEmpty) return '';

    // The picked slots can be disjoint (e.g. 2 and 8), so group them into
    // contiguous runs and format each run — a plain first→last range would
    // misrepresent {2, 8} as the whole 9 AM–3:50 PM block.
    final sorted = [...hours]..sort();
    final runs = <List<int>>[];
    for (final h in sorted) {
      if (runs.isNotEmpty && h == runs.last.last + 1) {
        runs.last.add(h);
      } else {
        runs.add([h]);
      }
    }
    return runs
        .map((run) => run.length == 1
            ? TimeSlotInfo.getHourSlotName(run.first)
            : TimeSlotInfo.getHourRangeName(run))
        .join(', ');
  }

  Future<void> _addTimeAvoidance() async {
    // Existing avoided hours per day → the dialog locks them, and we merge into
    // the same-day entry so there's one clean chip per day.
    final existing = <DayOfWeek, Set<int>>{};
    for (final a in _ctrl.avoidTimes) {
      existing.putIfAbsent(a.day, () => <int>{}).addAll(a.hours);
    }

    final result = await showDialog<TimeAvoidance>(
      context: context,
      builder: (context) => TimeAvoidanceDialog(disabledByDay: existing),
    );

    // Merging into the same-day entry lives in the controller.
    if (result != null && mounted) _ctrl.addTimeAvoidance(result);
  }

  Future<void> _addLabAvoidance() async {
    // Existing avoided lab hours per day → the dialog locks them, and we merge
    // into the same-day entry so there's one clean chip per day.
    final existing = <DayOfWeek, Set<int>>{};
    for (final a in _ctrl.avoidLabs) {
      existing.putIfAbsent(a.day, () => <int>{}).addAll(a.hours);
    }

    final result = await showDialog<LabAvoidance>(
      context: context,
      builder: (context) => LabAvoidanceDialog(disabledByDay: existing),
    );

    if (result != null && mounted) _ctrl.addLabAvoidance(result);
  }

  Future<void> _addInstructorAvoidance() async {
    // Get instructors organized by course and section type to avoid duplicates
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};
    final Set<String> seenInstructorsLower = <String>{};

    for (final courseCode in [..._ctrl.mandatoryCourses, ..._ctrl.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(
          courseCode: courseCode,
          courseTitle: 'Unknown',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 0,
          sections: [],
        ),
      );

      final sectionTypeInstructors = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      // Track seen instructors per section type to avoid duplicates within each section type
      final sectionTypeSeenLower = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      for (final section in course.sections) {
        if (section.instructor.isNotEmpty) {
          // Determine section type
          String sectionType = 'Lecture'; // default
          if (section.type.toString().contains('SectionType.L')) {
            sectionType = 'Lecture';
          } else if (section.type.toString().contains('SectionType.T')) {
            sectionType = 'Tutorial';
          } else if (section.type.toString().contains('SectionType.P')) {
            sectionType = 'Practical';
          }

          // Split comma-separated instructors into individual instructors
          final instructorList = section.instructor.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
          for (final instructor in instructorList) {
            final instructorLower = instructor.toLowerCase();

            // Only add if we haven't seen this instructor in this section type before
            if (!sectionTypeSeenLower[sectionType]!.contains(instructorLower)) {
              sectionTypeSeenLower[sectionType]!.add(instructorLower);
              sectionTypeInstructors[sectionType]!.add(instructor);

              // Also track globally to avoid duplicates across courses
              seenInstructorsLower.add(instructorLower);
            }
          }
        }
      }

      // Convert sets to sorted lists and filter out empty section types
      final filteredSectionInstructors = <String, List<String>>{};
      for (final entry in sectionTypeInstructors.entries) {
        if (entry.value.isNotEmpty) {
          filteredSectionInstructors[entry.key] = entry.value.toList()..sort();
        }
      }

      if (filteredSectionInstructors.isNotEmpty) {
        courseSectionInstructors[courseCode] = filteredSectionInstructors;
      }
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => InstructorAvoidanceDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentlyAvoided: _ctrl.avoidedInstructors,
      ),
    );

    if (result != null && mounted) {
      // Keys are "courseCode-sectionType-instructorName"; the name is rejoined
      // in case it contained hyphens of its own.
      _ctrl.addAvoidedInstructors(result
          .map((key) => key.split('-'))
          .where((parts) => parts.length >= 3)
          .map((parts) => parts.sublist(2).join('-')));
    }
  }

  Future<void> _showInstructorRankingDialog() async {
    // Get instructors organized by course and section type
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};

    for (final courseCode in [..._ctrl.mandatoryCourses, ..._ctrl.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );

      courseSectionInstructors[courseCode] = {
        'L': [],
        'P': [],
        'T': [],
      };

      for (final section in course.sections) {
        final sectionTypeStr = section.type.toString().split('.').last;
        if (courseSectionInstructors[courseCode]!.containsKey(sectionTypeStr)) {
          final instructor = section.instructor.trim();
          if (instructor.isNotEmpty &&
              !courseSectionInstructors[courseCode]![sectionTypeStr]!.contains(instructor)) {
            courseSectionInstructors[courseCode]![sectionTypeStr]!.add(instructor);
          }
        }
      }
    }

    final result = await showDialog<Map<String, InstructorRankings>>(
      context: context,
      builder: (context) => InstructorRankingDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentRankings: Map.from(_ctrl.instructorRankings),
      ),
    );

    if (result != null && mounted) _ctrl.setInstructorRankings(result);
  }

  Future<void> _generateTimetables() async {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
    if (isMobile && _tabController != null) {
      _tabController!.animateTo(1);
    }
    _compareSelection.value = const {};

    try {
      final result = await _ctrl.generate(widget.availableCourses);
      if (!mounted) return;
      if (result.ranked.isEmpty) {
        // A hard-constraint conflict explains itself in the results panel;
        // only the generic "no clash-free combo" case needs the dialog.
        if (result.unmetIntents.isEmpty) _showNoTimetablesDialog();
      }
    } catch (e) {
      ToastService.showError('Error generating timetables: $e');
    }
  }

  Widget _buildGeneratedTimetables() {
    // No Expanded here: the caller already wraps this in one. Nesting a second
    // put a Flex-only ParentDataWidget inside the AnimatedSwitcher's Stack,
    // which asserts as soon as any result is shown.
    return Card(
        margin: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Only the compare header and the card list care about the compare
            // selection, so the ValueListenableBuilders sit around those two
            // rather than around the panel. Ticking a checkbox on one card no
            // longer rebuilds the refine chips or the diagnosis banner.
            ValueListenableBuilder<Set<int>>(
              valueListenable: _compareSelection,
              builder: (context, selection, _) {
                final canCompare = selection.length >= 2;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Generated Timetables (${_ctrl.rankedTimetables.length})',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (selection.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: canCompare ? _showComparison : null,
                              icon: const Icon(Icons.compare_arrows, size: 18),
                              label: Text('Compare (${selection.length})'),
                              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                        ],
                      ),
                    ),
                    if (selection.isNotEmpty && !canCompare)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Select one more to compare',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            // The chips show whether each refinement is currently in effect,
            // which is constraint/importance state — so they have to watch
            // those too, or editing the same setting by hand in the Configure
            // panel leaves a chip stuck reading "on".
            _watch(
              Listenable.merge([_ctrl.constraints, _ctrl.importance]),
              _buildRefineChips,
            ),
            _buildDiagnosis(),
            Expanded(
              child: ListView.builder(
                itemCount: _ctrl.rankedTimetables.length,
                itemBuilder: (context, index) {
                  final ranked = _ctrl.rankedTimetables[index];
                  return ValueListenableBuilder<Set<int>>(
                    valueListenable: _compareSelection,
                    builder: (context, selection, _) => GeneratedTimetableCard(
                      ranked: ranked,
                      selectedForCompare: selection.contains(index),
                      onToggleCompare: () => _toggleCompare(index),
                      onSelect: () => widget.onTimetableSelected(ranked.timetable),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }

  /// One-tap "make the results more like this" nudges. Each tweaks a constraint
  /// or weight (reflected live in the Configure tab) and regenerates.
  /// Feasibility diagnosis: intents that no clash-free option could fully meet.
  /// This is the system doing the "is my wish list even possible" discovery the
  /// user can't, and handing back why.
  Widget _buildDiagnosis() {
    final notes = _ctrl.rankingResult?.unmetIntents ?? const <String>[];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppDesign.warning(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppDesign.warning(context).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppDesign.warning(context)),
                const SizedBox(width: 6),
                Text("Couldn't fully honour", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppDesign.warning(context))),
              ],
            ),
            const SizedBox(height: 4),
            ...notes.map((n) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $n', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85))),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildRefineChips() {
    if (_ctrl.rankedTimetables.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Text(
            'Refine:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in _refinements) _refineChip(r),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one-tap nudges under the results, and how to take each one back.
  ///
  /// `read`/`write` are a pair over one controller field, so applying stores
  /// the previous value and reverting restores exactly it. `isOn` is derived
  /// from live controller state rather than a local flag: editing the same
  /// setting by hand in the Configure panel releases the chip instead of
  /// leaving it stuck on claiming credit for a value it no longer set.
  List<_Refinement> get _refinements => [
        _Refinement<int>(
          label: 'Less packed',
          icon: Icons.compress,
          read: () => _ctrl.maxHoursPerDay,
          write: (v) => _ctrl.maxHoursPerDay = v,
          // A nudge, not a fixed target: each tap trims another hour.
          next: (current) => (current - 1).clamp(4, 12),
        ),
        _Refinement<AxisImportance?>(
          label: 'More free days',
          icon: Icons.weekend_outlined,
          read: () => _ctrl.axisImportance[RankAxis.freeDays],
          write: (v) => _ctrl.setAxisImportance(RankAxis.freeDays, v),
          next: (_) => AxisImportance.high,
        ),
        _Refinement<int?>(
          label: 'Later start',
          icon: Icons.wb_twilight_outlined,
          read: () => _ctrl.earliestStartSlot,
          write: (v) => _ctrl.earliestStartSlot = v,
          next: (_) => 2,
        ),
        _Refinement<bool>(
          label: 'Fewer gaps',
          icon: Icons.unfold_less,
          read: () => _ctrl.minimizeGaps,
          write: (v) => _ctrl.minimizeGaps = v,
          next: (_) => true,
        ),
      ];

  /// What each applied refinement set, and what it replaced. Keyed by label.
  final Map<String, ({Object? before, Object? applied})> _appliedRefinements = {};

  bool _isRefinementOn(_Refinement r) {
    final record = _appliedRefinements[r.label];
    return record != null && r.readDynamic() == record.applied;
  }

  Widget _refineChip(_Refinement r) {
    final on = _isRefinementOn(r);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        visualDensity: VisualDensity.compact,
        selected: on,
        showCheckmark: false,
        avatar: Icon(on ? Icons.check : r.icon,
            size: 15, color: on ? scheme.onSecondaryContainer : null),
        label: Text(on ? '${r.label} — on' : r.label,
            style: const TextStyle(fontSize: 12)),
        onSelected:
            _ctrl.isGenerating ? null : (_) => _toggleRefinement(r, on),
      ),
    );
  }

  /// No toast: the chip itself now carries the state persistently, so a
  /// transient "Refined: X" only repeated what the label already says.
  Future<void> _toggleRefinement(_Refinement r, bool isOn) async {
    if (isOn) {
      // Put back exactly what was there before this chip touched it.
      r.writeDynamic(_appliedRefinements.remove(r.label)!.before);
    } else {
      final before = r.readDynamic();
      final applied = r.nextDynamic(before);
      r.writeDynamic(applied);
      _appliedRefinements[r.label] = (before: before, applied: applied);
    }
    await _generateTimetables();
  }

  void _toggleCompare(int index) {
    final next = {..._compareSelection.value};
    if (!next.remove(index)) {
      if (next.length >= 3) {
        ToastService.showInfo('Compare up to 3 at a time');
        return;
      }
      next.add(index);
    }
    _compareSelection.value = next;
  }

  void _showComparison() {
    // Reuse the app's full comparison page by turning the picked generated
    // options into ephemeral timetables it can render.
    final selected = (_compareSelection.value.toList()..sort())
        .map((i) => _ctrl.rankedTimetables[i])
        .toList();
    final timetables = [
      for (var i = 0; i < selected.length; i++) _generatedToTimetable(selected[i].timetable, i),
    ];
    Navigator.push(
      context,
      FadeSlidePageRoute(page: TimetableComparisonScreen(presetTimetables: timetables)),
    );
  }

  tt_model.Timetable _generatedToTimetable(GeneratedTimetable g, int index) {
    final now = DateTime.now();
    return tt_model.Timetable(
      id: 'generated_$index',
      name: g.id,
      createdAt: now,
      updatedAt: now,
      campus: CampusService.currentCampus,
      availableCourses: widget.availableCourses,
      selectedSections: [
        for (final s in g.sections)
          tt_model.SelectedSection(courseCode: s.courseCode, sectionId: s.sectionId, section: s.section),
      ],
      clashWarnings: const [],
    );
  }

  void _showNoTimetablesDialog() {
    AppDialog.adaptive(
      context: context,
      title: 'No Valid Timetables Found',
      icon: Icons.warning_amber,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No conflict-free timetable combinations could be generated with your selected courses and constraints.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          const Text(
            'Try the following:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('• Remove some time constraints'),
          const Text('• Select fewer courses'),
          const Text('• Choose courses with more section options'),
          const Text('• Adjust your preferences'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All generated timetables are now conflict-free for better scheduling.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'OK',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
/// One reversible refine nudge over a single controller field.
///
/// Generic in the field's type so `read`/`write`/`next` stay type-safe at the
/// definition site; the `*Dynamic` accessors let the widget hold a
/// heterogeneous list of them.
class _Refinement<T> {
  const _Refinement({
    required this.label,
    required this.icon,
    required this.read,
    required this.write,
    required this.next,
  });

  final String label;
  final IconData icon;
  final T Function() read;
  final void Function(T) write;

  /// The value to move to, given what is there now.
  final T Function(T current) next;

  Object? readDynamic() => read();
  void writeDynamic(Object? value) => write(value as T);
  Object? nextDynamic(Object? current) => next(current as T);
}
