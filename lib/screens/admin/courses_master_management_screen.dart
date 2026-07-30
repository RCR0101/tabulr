import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../constants/app_constants.dart';
import '../../services/data/admin_data_service.dart';
import '../../services/data/campus_service.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/ui/secure_logger.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/course_code.dart';
import '../../utils/debouncer.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/app_search_field.dart';
import '../../widgets/common/app_tappable.dart';
import '../../widgets/common/empty_state_widget.dart';

/// Edits `courses_master` — the curated catalogue of every course that exists,
/// offered this semester or not.
///
/// Separate from [CourseManagementScreen] on purpose. That screen edits the
/// *timetable*: it lists documents from `campuses/{id}/timetable` and writes a
/// master row alongside each one, so it can only reach the ~420 courses running
/// this semester, and saving through it would invent a timetable document for a
/// catalogue-only course. 2,429 of the 2,852 catalogue rows are unreachable
/// there. This screen touches the catalogue and nothing else.
class CoursesMasterManagementScreen extends StatefulWidget {
  const CoursesMasterManagementScreen({super.key});

  @override
  State<CoursesMasterManagementScreen> createState() =>
      _CoursesMasterManagementScreenState();
}

class _CoursesMasterManagementScreenState
    extends State<CoursesMasterManagementScreen> {
  static const _campusIds = CampusConstants.ids;
  static const _campusLabels = CampusConstants.labels;

  final _crud = AdminDataService();
  final _searchController = TextEditingController();
  final _debounce = Debouncer(duration: const Duration(milliseconds: 400));

  String _campusId = CampusService.campusId;
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;

  /// Guards against an earlier campus's load landing after a later one and
  /// overwriting it with the wrong catalogue.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _load(force: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    try {
      final query = _searchController.text.trim();
      final rows = await _crud.fetchMasterCourses(_campusId,
          query: query, forceRefresh: force);
      // Unfiltered count, so the header can say "12 of 2,852" rather than
      // implying the catalogue only holds what the search matched.
      final all = query.isEmpty
          ? rows
          : await _crud.fetchMasterCourses(_campusId);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _rows = rows;
        _total = all.length;
        _loading = false;
      });
    } catch (e) {
      SecureLogger.error('CoursesMasterAdmin', 'Load failed: $e');
      if (!mounted || seq != _loadSeq) return;
      setState(() => _loading = false);
      ToastService.showError('Could not load the catalogue');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.inventory_2_outlined,
          title: 'Courses Master',
          subtitle: _loading
              ? 'Loading…'
              : '${_rows.length} of $_total in ${_campusLabels[_campusId]}',
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload from Firestore',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('Add course'),
      ),
      body: Column(
        children: [
          _controls(),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd,
          AppDesign.spacingSm + 4, AppDesign.spacingMd, AppDesign.spacingSm),
      child: Row(
        children: [
          AppDropdown<String>(
            value: _campusId,
            width: 150,
            height: 48,
            isExpanded: true,
            items: [
              for (final id in _campusIds)
                DropdownMenuItem(value: id, child: Text(_campusLabels[id]!)),
            ],
            onChanged: (id) {
              if (id == null || id == _campusId) return;
              setState(() => _campusId = id);
              _load();
            },
          ),
          const SizedBox(width: AppDesign.spacingSm + 4),
          Expanded(
            child: AppSearchField(
              controller: _searchController,
              hint: 'Search by code or title',
              onChanged: (_) => _debounce.run(_load),
              onClear: () {
                _searchController.clear();
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off,
        title: 'No course matches',
        subtitle: _searchController.text.trim().isEmpty
            ? 'The catalogue is empty for ${_campusLabels[_campusId]}.'
            : 'Nothing in ${_campusLabels[_campusId]} matches '
                '"${_searchController.text.trim()}".',
      );
    }
    return ListView.builder(
      // 2,852 rows: build only what is on screen.
      scrollCacheExtent: ScrollCacheExtent.pixels(600),
      itemCount: _rows.length,
      itemBuilder: (context, index) => _row(_rows[index], index),
    );
  }

  Widget _row(Map<String, dynamic> row, int index) {
    final scheme = Theme.of(context).colorScheme;
    final code = row['course_code'] as String? ?? '';
    final title = row['title'] as String? ?? '';
    final credits = (row['credits'] as num?) ?? 0;
    final type = row['type'] as String? ?? 'Normal';

    return AppTappable(
      onTap: () => _openEditor(row),
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
                  Text(code,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(
                    // A code with no title is the thing this screen exists to
                    // fix, so it is called out rather than left blank.
                    title.isEmpty ? 'No title' : title,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontStyle:
                            title.isEmpty ? FontStyle.italic : FontStyle.normal,
                        color: title.isEmpty
                            ? scheme.error
                            : scheme.onSurface.withValues(alpha: 0.62)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (type != 'Normal') ...[
              _pill(type, scheme.tertiary),
              const SizedBox(width: AppDesign.spacingSm),
            ],
            SizedBox(
              width: 52,
              child: Text(
                credits == 0 && (row['credit_hours'] as num? ?? 0) > 0
                    ? '${row['credit_hours']} CH'
                    : '${credits == credits.roundToDouble() ? credits.toInt() : credits}U',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: credits == 0
                        ? scheme.error
                        : scheme.onSurface.withValues(alpha: 0.75)),
              ),
            ),
            const SizedBox(width: AppDesign.spacingSm),
            Icon(Icons.chevron_right,
                size: AppDesign.iconSizeMd, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: AppDesign.borderRadiusXs,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: colour)),
    );
  }

  /// [row] null means add. On an existing row the code is fixed: it is the
  /// document id, so changing it would create a second document rather than
  /// rename one, and silently orphan every prerequisite and minor pointing at
  /// the old code.
  Future<void> _openEditor(Map<String, dynamic>? row) async {
    final isNew = row == null;
    final codeController =
        TextEditingController(text: row?['course_code'] as String? ?? '');
    final titleController =
        TextEditingController(text: row?['title'] as String? ?? '');
    final creditsController = TextEditingController(
        text: ((row?['credits'] as num?) ?? 0).toString());
    final creditHoursController = TextEditingController(
        text: ((row?['credit_hours'] as num?) ?? 0).toString());
    var type = row?['type'] as String? ?? 'Normal';
    var allCampuses = false;

    final saved = await AppDialog.adaptive<bool>(
      context: context,
      icon: isNew ? Icons.add : Icons.edit_outlined,
      title: isNew ? 'Add a course' : (row['course_code'] as String? ?? 'Edit'),
      content: StatefulBuilder(
        builder: (context, setInner) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDesign.maxDialogWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNew)
                TextField(
                  controller: codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: AppDesign.inputDecoration(context,
                      label: 'Course code', hint: 'CS F211'),
                ),
              if (isNew) const SizedBox(height: AppDesign.spacingMd),
              TextField(
                controller: titleController,
                autofocus: !isNew,
                decoration:
                    AppDesign.inputDecoration(context, label: 'Title'),
              ),
              const SizedBox(height: AppDesign.spacingMd),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: creditsController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: AppDesign.inputDecoration(context,
                          label: 'Units'),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spacingSm),
                  // Contact hours, for the courses the booklet publishes no
                  // unit count for. Its own number: CHEM U101 is 3 units and 7
                  // credit hours, so this is never units x 3.
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: creditHoursController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: AppDesign.inputDecoration(context,
                          label: 'Credit hrs'),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spacingMd),
                  Expanded(
                    child: AppDropdown<String>(
                      value: type,
                      height: 48,
                      isExpanded: true,
                      items: [
                        for (final t in AdminDataService.courseTypes)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (t) {
                        if (t != null) setInner(() => type = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesign.spacingSm),
              // The catalogue is stored per campus and has drifted: 21 rows
              // differ between Hyderabad and Pilani, some of it deliberate.
              // Off by default so an edit cannot quietly flatten that.
              CheckboxListTile(
                value: allCampuses,
                onChanged: (v) => setInner(() => allCampuses = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Apply to all three campuses',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  allCampuses
                      ? 'Writes to Hyderabad, Pilani and Goa'
                      : 'Writes to ${_campusLabels[_campusId]} only',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!isNew)
          AppButton(
            label: 'Delete',
            variant: AppButtonVariant.danger,
            onTap: () => Navigator.of(context).pop(false),
          ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (!mounted) return;
    final targets = allCampuses ? _campusIds : [_campusId];

    if (saved == false) {
      await _confirmDelete(row!['course_code'] as String, targets);
      return;
    }
    if (saved != true) return;

    final code = codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ToastService.showError('A course code is required');
      return;
    }
    if (isNew &&
        _rows.any((r) => normalizeCourseCode(r['course_code'] as String? ?? '') ==
            normalizeCourseCode(code))) {
      ToastService.showError('$code is already in the catalogue');
      return;
    }
    final title = titleController.text.trim();
    if (title.isEmpty) {
      // A row with no usable title is worse than no row: it masks the gap while
      // still rendering the bare code everywhere. Same rule the uploader applies.
      ToastService.showError('A title is required — a bare code helps nobody');
      return;
    }

    try {
      await _crud.saveMasterCourse(
        campusIds: targets,
        courseCode: code,
        title: title,
        credits: double.tryParse(creditsController.text.trim()) ?? 0,
        creditHours:
            double.tryParse(creditHoursController.text.trim()) ?? 0,
        type: type,
      );
      // The app-wide catalogue is now stale in memory; drop it so titles and
      // credits re-resolve from the bundle this just rewrote.
      CoursesMasterService().clear();
      if (!mounted) return;
      ToastService.showSuccess(
          'Saved $code to ${targets.length == 1 ? _campusLabels[targets.first] : 'all campuses'}');
      await _load(force: true);
    } catch (e) {
      SecureLogger.error('CoursesMasterAdmin', 'Save failed: $e');
      if (mounted) ToastService.showError('Save failed: $e');
    }
  }

  /// Deleting a catalogue row leaves anything pointing at the code behind, so
  /// the confirmation names what it is about to orphan rather than asking
  /// "are you sure".
  Future<void> _confirmDelete(String courseCode, List<String> targets) async {
    List<String> references = const [];
    try {
      references = await _crud.findCourseCodeReferences(_campusId, courseCode);
    } catch (e) {
      SecureLogger.error('CoursesMasterAdmin', 'Reference scan failed: $e');
      references = ['Could not check for references — $e'];
    }
    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    final confirmed = await AppDialog.adaptive<bool>(
      context: context,
      icon: Icons.delete_outline,
      iconColor: scheme.error,
      title: 'Delete $courseCode?',
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDesign.maxDialogWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targets.length == 1
                  ? 'Removes the catalogue row from ${_campusLabels[targets.first]}. '
                      'The timetable document, if any, is left alone.'
                  : 'Removes the catalogue row from all three campuses. '
                      'Timetable documents are left alone.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppDesign.spacingMd),
            if (references.isEmpty)
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: AppDesign.iconSizeSm,
                      color: AppDesign.success(context)),
                  const SizedBox(width: AppDesign.spacingSm),
                  const Expanded(
                    child: Text('Nothing else refers to this code.',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              )
            else ...[
              Text('Still referred to by:',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.error)),
              const SizedBox(height: AppDesign.spacingSm),
              for (final reference in references)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $reference',
                      style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: AppDesign.spacingSm),
              Text(
                'These keep the code and will render it with no title.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Delete',
          variant: AppButtonVariant.danger,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirmed != true || !mounted) return;
    try {
      await _crud.deleteMasterCourse(
          campusIds: targets, courseCode: courseCode);
      CoursesMasterService().clear();
      if (!mounted) return;
      ToastService.showSuccess('Deleted $courseCode');
      await _load(force: true);
    } catch (e) {
      SecureLogger.error('CoursesMasterAdmin', 'Delete failed: $e');
      if (mounted) ToastService.showError('Delete failed: $e');
    }
  }
}
