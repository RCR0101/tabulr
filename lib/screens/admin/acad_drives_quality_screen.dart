import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/acad_coverage.dart';
import '../../models/acad_resource_type.dart';
import '../../services/data/acad_drives_service.dart';
import '../../services/data/admin_data_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/course_picker_sheet.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../../widgets/common/tabulr_surface.dart';

/// Keeping Acad Drives right and growing it:
/// - Reports: files students flagged (wrong course, wrong type, broken, not
///   academic), each fixed in one tap.
/// - Coverage: courses running this semester with no files or no past papers,
///   ranked by how many students asked for them.
class AcadDrivesQualityScreen extends StatefulWidget {
  const AcadDrivesQualityScreen({
    super.key,
    this.loadCourses,
    this.loadIndex,
    this.pickCourse,
  });

  /// The running courses (tests). Defaults to the Hyderabad timetable.
  final Future<List<Map<String, dynamic>>> Function()? loadCourses;

  /// The drives index (tests). Defaults to the one students see.
  final Future<List<Map<String, dynamic>>> Function()? loadIndex;

  /// Replaces the course picker sheet (tests).
  final Future<String?> Function(BuildContext)? pickCourse;

  @override
  State<AcadDrivesQualityScreen> createState() => _AcadDrivesQualityScreenState();
}

class _AcadDrivesQualityScreenState extends State<AcadDrivesQualityScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppDesign.appBar(
          context,
          titleWidget: AppDesign.iconTitle(
            context,
            icon: Icons.fact_check_outlined,
            title: 'Acad Drives Quality',
            subtitle: 'Student reports and missing courses',
          ),
          centerTitle: false,
          bottom: const TabBar(tabs: [Tab(text: 'Reports'), Tab(text: 'Coverage')]),
        ),
        body: TabBarView(
          children: [
            _ReportsTab(pickCourse: widget.pickCourse),
            _CoverageTab(loadCourses: widget.loadCourses, loadIndex: widget.loadIndex),
          ],
        ),
      ),
    );
  }
}

// ─── Reports ───

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({this.pickCourse});

  final Future<String?> Function(BuildContext)? pickCourse;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final _service = AcadDrivesService();
  late final _stream = _service.openReports();
  final Set<String> _busy = {};

  Future<void> _resolve(
    QueryDocumentSnapshot<Map<String, dynamic>> r, {
    String? course,
    String? type,
    bool hide = false,
  }) async {
    setState(() => _busy.add(r.id));
    try {
      await _service.resolveReport(r, course: course, type: type, hide: hide);
    } catch (e) {
      ToastService.showError('Could not update: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
    ToastService.showSuccess(course == null && type == null && !hide ? 'Dismissed' : 'Fixed');
  }

  Future<void> _pickAndMove(QueryDocumentSnapshot<Map<String, dynamic>> r) async {
    final code = widget.pickCourse != null
        ? await widget.pickCourse!(context)
        : (await showCoursePicker(context, title: 'Move it to'))?.firstOrNull?.courseCode;
    if (code != null && mounted) await _resolve(r, course: code);
  }

  Future<void> _pickType(QueryDocumentSnapshot<Map<String, dynamic>> r) async {
    final type = await showDialog<AcadResourceType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('It is actually'),
        children: [
          for (final t in AcadResourceType.values)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, t), child: Text(t.label)),
        ],
      ),
    );
    if (type != null && mounted) await _resolve(r, type: type.key);
  }

  Future<void> _openFile(String fileId) async {
    final files = await _service.fetchFilesByIds({fileId});
    final url = files.isEmpty ? null : '${files.first['url'] ?? ''}';
    if (url == null || !url.startsWith('https://')) {
      ToastService.showError('That file has no link any more');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: EmptyStateWidget(
              icon: Icons.error_outline,
              title: 'Could not load reports',
              subtitle: 'Check your admin access and try again.',
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final reports = snap.data!;
        if (reports.isEmpty) {
          return const Center(
            child: EmptyStateWidget(
              icon: Icons.verified_outlined,
              title: 'No open reports',
              subtitle: 'Files students flag from Acad Drives show up here.',
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              children: [
                Text(
                  'Fixes show at once inside the course; course file counts catch up at the next sync.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppDesign.muted(context)),
                ),
                const SizedBox(height: AppDesign.spacingSm),
                for (final r in reports) _reportCard(context, r),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reportCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> r) {
    final text = Theme.of(context).textTheme;
    final d = r.data();
    final problem = AcadFileProblem.fromKey(d['problem'] as String?);
    final suggestedCourse = d['suggestedCourse'] as String?;
    final suggestedType = d['suggestedType'] == null ? null : AcadResourceType.fromKey(d['suggestedType'] as String);
    final current = AcadResourceType.fromKey(d['currentType'] as String?);
    final busy = _busy.contains(r.id);
    final muted = text.bodySmall?.copyWith(color: AppDesign.muted(context));

    final actions = <Widget>[
      TextButton(onPressed: busy ? null : () => _resolve(r), child: const Text('Dismiss')),
      switch (problem) {
        AcadFileProblem.wrongCourse => suggestedCourse != null
            ? FilledButton(
                onPressed: busy ? null : () => _resolve(r, course: suggestedCourse),
                child: Text('Move to $suggestedCourse'),
              )
            : FilledButton(onPressed: busy ? null : () => _pickAndMove(r), child: const Text('Move to…')),
        AcadFileProblem.wrongType => suggestedType != null
            ? FilledButton(
                onPressed: busy ? null : () => _resolve(r, type: suggestedType.key),
                child: Text('Make it ${suggestedType.label}'),
              )
            : FilledButton(onPressed: busy ? null : () => _pickType(r), child: const Text('Change type…')),
        _ => FilledButton(
            onPressed: busy ? null : () => _resolve(r, hide: true),
            child: const Text('Hide file'),
          ),
      },
    ];
    // The other fixes stay one menu away when the student picked the wrong problem.
    final more = PopupMenuButton<String>(
      tooltip: 'Other fixes',
      enabled: !busy,
      onSelected: (v) => switch (v) {
        'move' => _pickAndMove(r),
        'type' => _pickType(r),
        _ => _resolve(r, hide: true),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'move', child: Text('Move to another course…')),
        PopupMenuItem(value: 'type', child: Text('Change type…')),
        PopupMenuItem(value: 'hide', child: Text('Hide file')),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      child: TabulrSurface(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${d['fileName'] ?? d['fileId']}',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Open the file',
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  onPressed: () => _openFile('${d['fileId']}'),
                ),
              ],
            ),
            Text(
              [
                '${d['currentCourse'] ?? ''}'.isEmpty ? 'no course' : '${d['currentCourse']}',
                current.label,
                if ('${d['driveName'] ?? ''}'.isNotEmpty) 'drive: ${d['driveName']}',
              ].join('  ·  '),
              style: muted,
            ),
            const SizedBox(height: AppDesign.spacingSm),
            Text(problem?.label ?? '${d['problem']}',
                style: text.bodyMedium?.copyWith(color: AppDesign.warning(context), fontWeight: FontWeight.w600)),
            if ('${d['note'] ?? ''}'.isNotEmpty) Text('"${d['note']}"', style: text.bodyMedium),
            Text('Reported by ${d['reportedBy']}', style: muted),
            const SizedBox(height: AppDesign.spacingSm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [...actions, more],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Coverage ───

class _CoverageTab extends StatefulWidget {
  const _CoverageTab({this.loadCourses, this.loadIndex});

  final Future<List<Map<String, dynamic>>> Function()? loadCourses;
  final Future<List<Map<String, dynamic>>> Function()? loadIndex;

  @override
  State<_CoverageTab> createState() => _CoverageTabState();
}

class _CoverageTabState extends State<_CoverageTab> {
  final _service = AcadDrivesService();
  List<CoverageRow>? _rows;
  String? _error;
  CoverageFilter _filter = CoverageFilter.gaps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        widget.loadCourses?.call() ?? AdminDataService().fetchCourses('hyderabad'),
        widget.loadIndex?.call() ?? _service.fetchAllCoursesData(),
        _service.fetchRequests(),
      ]);
      if (mounted) setState(() => _rows = buildCoverage(results[0], results[1], results[2]));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _clear(CoverageRow row) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Clear requests for ${row.code}?',
      message: 'Do this once the course has what students asked for. '
          'They can ask again if it is still missing.',
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    try {
      await _service.clearRequests(row.code);
      await _load();
    } catch (e) {
      ToastService.showError('Could not clear: $e');
    }
  }

  static const _filterLabels = {
    CoverageFilter.gaps: 'All gaps',
    CoverageFilter.requested: 'Asked for',
    CoverageFilter.noFiles: 'No files',
    CoverageFilter.noPastPapers: 'No past papers',
  };

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load coverage: $_error'),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final all = _rows;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final rows = filterCoverage(all, _filter);
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in CoverageFilter.values)
                    ChoiceChip(
                      label: Text('${_filterLabels[f]} · ${filterCoverage(all, f).length}'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: AppDesign.spacingSm),
              Text(
                'Courses in this semester\'s Hyderabad timetable, plus any a student asked for. '
                'Look for a senior with a drive for the top ones, and point them to Submit resource.',
                style: text.bodySmall?.copyWith(color: AppDesign.muted(context)),
              ),
              const SizedBox(height: AppDesign.spacingSm),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyStateWidget(icon: Icons.check_circle_outline, title: 'Nothing here'),
                ),
              for (final r in rows) _row(context, r),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, CoverageRow r) {
    final text = Theme.of(context).textTheme;
    final asked = [
      for (final e in r.requestsByType.entries)
        '${e.key == 'any' ? 'anything' : AcadResourceType.fromKey(e.key).label.toLowerCase()} ×${e.value}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text([r.code, if (r.title.isNotEmpty) r.title].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              r.noFiles ? 'no files' : '${r.files} files',
              if (!r.noFiles) r.noPastPapers ? 'no past papers' : '${r.pastPapers} past papers',
              if (!r.running) 'not running this semester',
            ].join('  ·  '),
            style: text.bodySmall?.copyWith(color: AppDesign.muted(context)),
          ),
          if (r.requesters > 0)
            Text(
              '${r.requesters} ${r.requesters == 1 ? 'student' : 'students'} asked: ${asked.join(', ')}',
              style: text.bodySmall?.copyWith(color: AppDesign.warning(context), fontWeight: FontWeight.w600),
            ),
          for (final n in r.notes.take(2)) Text('"$n"', style: text.bodySmall),
        ],
      ),
      trailing: r.requests > 0
          ? TextButton(onPressed: () => _clear(r), child: const Text('Clear'))
          : null,
    );
  }
}
