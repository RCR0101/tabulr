import 'package:flutter/material.dart';
import '../repositories/prerequisites_repository.dart';
import '../services/core/bottleneck_analyzer.dart';
import '../services/core/degree_auditor.dart';
import '../services/data/academic_record_service.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/course_history_service.dart';
import '../services/data/profile_service.dart';
import '../utils/course_code.dart';
import '../utils/design_constants.dart';
import '../utils/page_info_helper.dart';

/// P1 graduation audit: the student's transcript diffed against their degree's
/// core requirements, plus how many electives they've already cleared. See
/// [DegreeAuditor] for the scope (core-backed; no invented elective targets).
class DegreeAuditScreen extends StatefulWidget {
  const DegreeAuditScreen({super.key});

  @override
  State<DegreeAuditScreen> createState() => _DegreeAuditScreenState();
}

class _DegreeAuditScreenState extends State<DegreeAuditScreen> {
  bool _loading = true;
  String? _branch; // resolved primary branch, for the "set your branch" prompt
  bool _recordEmpty = false;
  DegreeAudit? _audit;
  BottleneckReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await ProfileService().load();
    final primary = profile.primaryBranch;
    if (primary == null || primary.isEmpty) {
      setState(() {
        _loading = false;
        _branch = null;
      });
      return;
    }

    final record = await AcademicRecordService().load();
    final service = BranchStructureService();
    final cdcs = await service.coreSlotsBySemester(
      primary,
      secondaryBranch: profile.secondaryBranch,
    );
    final dels = <String>{...await service.getDELs(primary)};
    final huels = <String>{...await service.getHUELs(primary)};
    if (profile.secondaryBranch != null &&
        profile.secondaryBranch!.isNotEmpty) {
      dels.addAll(await service.getDELs(profile.secondaryBranch!));
      huels.addAll(await service.getHUELs(profile.secondaryBranch!));
    }

    final audit = DegreeAuditor.audit(
      cdcsBySemester: cdcs,
      record: record,
      dels: dels,
      huels: huels,
    );
    final report = await _analyzeBottlenecks(audit);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _branch = primary;
      _recordEmpty = record.isEmpty;
      _audit = audit;
      _report = report;
    });
  }

  /// P2: which remaining cores gate the rest and run in only one semester, plus
  /// the longest prereq chain still ahead. Best-effort — if the history or
  /// prereq data can't load, the audit above still renders.
  Future<BottleneckReport?> _analyzeBottlenecks(DegreeAudit audit) async {
    final remaining = <String>{
      for (final r in [
        ...audit.pendingRequirements,
        ...audit.failedRequirements,
      ])
        normalizeCourseCode(r.slot.options.first),
    };
    if (remaining.isEmpty) return null;

    try {
      await CourseHistoryService().load();
      final history = CourseHistoryService().history;
      final parity = <String, OfferingParity>{
        for (final t in history.courses)
          normalizeCourseCode(t.courseCode): BottleneckAnalyzer.parityOf(
            t.offerings.map((o) => o.term),
          ),
      };

      final withPrereqs =
          await PrerequisitesRepository().getCoursesWithPrerequisites();
      final edges = <String, Set<String>>{
        for (final cp in withPrereqs)
          normalizeCourseCode(cp.courseCode): {
            for (final g in cp.groups)
              for (final o in g.options) normalizeCourseCode(o.courseCode),
          },
      };

      return BottleneckAnalyzer.analyze(
        remaining: remaining,
        parity: parity,
        prereqEdges: edges,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Degree Audit',
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.degreeAudit),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_branch == null) {
      return _prompt(
        context,
        Icons.badge_outlined,
        'Set your branch to see your degree audit — Profile › Branch.',
      );
    }
    final audit = _audit;
    if (audit == null || audit.total == 0) {
      return _prompt(
        context,
        Icons.school_outlined,
        'No core-course data is available for your branch yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      children: [
        _headerCard(context, audit),
        if (_recordEmpty) ...[
          const SizedBox(height: AppDesign.spacingMd),
          _prompt(
            context,
            Icons.calculate_outlined,
            'Fill in your grades in the CGPA Calculator to track completion.',
            embedded: true,
          ),
        ],
        const SizedBox(height: AppDesign.spacingMd),
        _electiveCard(context, audit),
        if (_report != null &&
            (_report!.bottlenecks.isNotEmpty ||
                _report!.criticalPathLength > 1)) ...[
          const SizedBox(height: AppDesign.spacingMd),
          _bottleneckCard(context, _report!),
        ],
        const SizedBox(height: AppDesign.spacingMd),
        for (final entry in audit.bySemester.entries) ...[
          _semesterCard(context, entry.key, entry.value),
          const SizedBox(height: AppDesign.spacingSm),
        ],
        const SizedBox(height: AppDesign.spacingLg),
        Text(
          'Core (CDC) courses only. Elective and total-credit requirements '
          'aren\'t published in the branch data, so they\'re shown as counts, '
          'not "remaining".',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
      ],
    );
  }

  Widget _headerCard(BuildContext context, DegreeAudit audit) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Core courses cleared',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '${audit.cleared} / ${audit.total}',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: audit.fractionCleared,
              minHeight: 10,
              backgroundColor: scheme.surface.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(AppDesign.success(context)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (audit.failed > 0)
                _stat(context, '${audit.failed} to retake', scheme.error),
              if (audit.pending > 0)
                _stat(
                  context,
                  '${audit.pending} not taken yet',
                  scheme.onSurface.withValues(alpha: 0.6),
                ),
              if (audit.coreComplete)
                _stat(
                  context,
                  'All core courses done',
                  AppDesign.success(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      );

  Widget _bottleneckCard(BuildContext context, BottleneckReport report) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      title: 'Timing bottlenecks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in report.bottlenecks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.priority_high, size: 18, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: b.code,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text:
                                '  ·  ${b.parity.label}  ·  gates ${b.gatesDownstream} core${b.gatesDownstream == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (report.criticalPathLength > 1) ...[
            if (report.bottlenecks.isNotEmpty) const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Longest chain ahead: ',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    TextSpan(
                      text: report.criticalPath.join('  →  '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text:
                          '  — at least ${report.criticalPathLength} semesters back-to-back.',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _electiveCard(BuildContext context, DegreeAudit audit) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      title: 'Electives cleared',
      child: Row(
        children: [
          _electiveTile(
            context,
            'Discipline',
            audit.clearedDels,
            scheme.secondary,
          ),
          const SizedBox(width: AppDesign.spacingMd),
          _electiveTile(
            context,
            'Humanities',
            audit.clearedHuels,
            scheme.tertiary,
          ),
        ],
      ),
    );
  }

  Widget _electiveTile(BuildContext context, String label, int count, Color c) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _semesterCard(
    BuildContext context,
    String semester,
    List<CoreRequirement> reqs,
  ) {
    return _card(
      context,
      title: 'Semester $semester',
      child: Column(
        children: [for (final r in reqs) _requirementRow(context, r)],
      ),
    );
  }

  Widget _requirementRow(BuildContext context, CoreRequirement r) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (r.status) {
      CoreStatus.cleared => (Icons.check_circle, AppDesign.success(context)),
      CoreStatus.failed => (Icons.replay_circle_filled, scheme.error),
      CoreStatus.pending => (
          Icons.radio_button_unchecked,
          scheme.onSurface.withValues(alpha: 0.35),
        ),
    };
    // A choice shows its options as "A or B"; a cleared choice names the one taken.
    final label = r.status == CoreStatus.cleared && r.slot.isChoice
        ? '${r.clearedBy}  (from ${r.slot.options.join(" / ")})'
        : r.slot.options.join('  or  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface,
                decoration:
                    r.status == CoreStatus.cleared ? TextDecoration.none : null,
              ),
            ),
          ),
          if (r.status == CoreStatus.failed)
            Text(
              'retake',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _prompt(
    BuildContext context,
    IconData icon,
    String msg, {
    bool embedded = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final body = Row(
      children: [
        Icon(icon, color: scheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8)),
          ),
        ),
      ],
    );
    if (embedded) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: body,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingLg),
        child: body,
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
