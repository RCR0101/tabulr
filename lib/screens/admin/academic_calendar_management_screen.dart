import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../models/academic_calendar_event.dart';
import '../../services/data/academic_calendar_service.dart';
import '../../services/data/admin_service.dart';
import '../../services/ui/page_leave_warning_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_dialog.dart';

/// Admin review + CRUD for a campus's academic calendar
/// (`campuses/{id}/academicCalendar/current`). The `upload_timetable` Cloud
/// Function drafts the entries from the booklet; this is where an admin fixes
/// the parser's rough edges (wrapped labels, mis-categorised rows) before the
/// calendar overlay and ICS reminders consume them.
class AcademicCalendarManagementScreen extends StatefulWidget {
  const AcademicCalendarManagementScreen({super.key});

  @override
  State<AcademicCalendarManagementScreen> createState() =>
      _AcademicCalendarManagementScreenState();
}

class _AcademicCalendarManagementScreenState
    extends State<AcademicCalendarManagementScreen> {
  static const _leaveSource = 'academicCalendar';

  final _service = AcademicCalendarService();

  String _campusId = CampusConstants.ids.first;
  List<AcademicCalendarEvent> _events = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    PageLeaveWarningService().clear(_leaveSource);
    super.dispose();
  }

  /// One choke point for dirty state so the Save button and the web
  /// refresh/close prompt can't fall out of step.
  void _setDirty(bool value) {
    if (_dirty != value) setState(() => _dirty = value);
    PageLeaveWarningService().setUnsaved(_leaveSource, value);
  }

  Future<bool> _confirmDiscard({String confirmLabel = 'Leave'}) =>
      AppDialog.confirm(
        context: context,
        title: 'Unsaved Changes',
        message: 'You have unsaved calendar changes that will be lost. Continue?',
        confirmLabel: confirmLabel,
        cancelLabel: 'Stay',
        isDangerous: true,
      );

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events = await _service.load(campusId: _campusId, force: true);
      if (!mounted) return;
      setState(() {
        _events = [...events];
        _loading = false;
      });
      _setDirty(false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError('Failed to load calendar');
    }
  }

  Future<void> _switchCampus(String id) async {
    if (id == _campusId) return;
    if (_dirty && !await _confirmDiscard(confirmLabel: 'Switch')) return;
    setState(() => _campusId = id);
    await _load();
  }

  void _sortEvents() =>
      _events.sort((a, b) => a.date.compareTo(b.date));

  Future<void> _addOrEdit([int? index]) async {
    final result = await showDialog<AcademicCalendarEvent>(
      context: context,
      builder: (_) => _EventEditorDialog(
        initial: index == null ? null : _events[index],
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _events.add(result);
      } else {
        _events[index] = result;
      }
      _sortEvents();
    });
    _setDirty(true);
  }

  void _delete(int index) {
    setState(() => _events.removeAt(index));
    _setDirty(true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.save(_campusId, _events);
      if (!mounted) return;
      _setDirty(false);
      ToastService.showSuccess('Calendar saved for ${_campusLabel(_campusId)}');
    } catch (e) {
      ToastService.showError('Save failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _campusLabel(String id) => CampusConstants.labels[id] ?? id;

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Academic Calendar'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && navigator.canPop()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppDesign.appBar(context, title: 'Academic Calendar', actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: AppDesign.spacingSm),
              child: TextButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add entry',
            onPressed: () => _addOrEdit(),
          ),
        ]),
        body: Column(
          children: [
            _campusSelector(),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _events.isEmpty
                      ? _emptyState()
                      : _list(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campusSelector() {
    return Padding(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      child: Row(
        children: [
          for (final id in CampusConstants.ids)
            Padding(
              padding: const EdgeInsets.only(right: AppDesign.spacingSm),
              child: ChoiceChip(
                label: Text(_campusLabel(id)),
                selected: id == _campusId,
                onSelected: (_) => _switchCampus(id),
              ),
            ),
          const Spacer(),
          if (!_loading)
            Text('${_events.length} entries',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined,
                size: 48,
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
            const SizedBox(height: AppDesign.spacingMd),
            Text('No calendar for ${_campusLabel(_campusId)} yet',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppDesign.spacingSm),
            Text(
              'Upload a timetable with an academic-calendar page range, '
              'or add entries manually with +.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppDesign.spacingXl),
      itemCount: _events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _events[i];
        return ListTile(
          leading: _categoryChip(e.category),
          title: Text(e.label),
          subtitle: Text(_dateLabel(e)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                onPressed: () => _addOrEdit(i),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                onPressed: () => _delete(i),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryChip(AcademicEventCategory c) {
    final color = academicCategoryColor(context, c);
    return Container(
      width: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        academicCategoryShort(c),
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _dateLabel(AcademicCalendarEvent e) {
    String fmt(DateTime d) =>
        '${d.day} ${DayConstants.monthNames[d.month]} ${d.year}';
    return e.isRange ? '${fmt(e.date)} – ${fmt(e.endDate!)}' : fmt(e.date);
  }
}

/// Dialog to add or edit one calendar entry.
class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({this.initial});
  final AcademicCalendarEvent? initial;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  late final TextEditingController _labelCtrl;
  late DateTime _date;
  DateTime? _endDate;
  late AcademicEventCategory _category;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _date = e?.date ?? DateTime.now();
    _endDate = e?.endDate;
    _category = e?.category ?? AcademicEventCategory.event;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isEnd}) async {
    final initial = isEnd ? (_endDate ?? _date) : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (isEnd) {
        _endDate = picked;
      } else {
        _date = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      }
    });
  }

  static String _fmt(DateTime d) =>
      '${d.day} ${DayConstants.monthNames[d.month]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add entry' : 'Edit entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _labelCtrl,
              autofocus: true,
              decoration: AppDesign.inputDecoration(context, hint: 'Description'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: AppDesign.spacingMd),
            DropdownButtonFormField<AcademicEventCategory>(
              initialValue: _category,
              decoration: AppDesign.inputDecoration(context, hint: 'Category'),
              items: [
                for (final c in AcademicEventCategory.values)
                  DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppDesign.spacingMd),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_fmt(_date)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () => _pickDate(isEnd: false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('End date (optional)'),
              subtitle: Text(_endDate == null ? 'Single day' : _fmt(_endDate!)),
              trailing: _endDate == null
                  ? const Icon(Icons.add, size: 18)
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _endDate = null),
                    ),
              onTap: () => _pickDate(isEnd: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _labelCtrl.text.trim();
            if (label.isEmpty) {
              ToastService.showWarning('Add a description first.');
              return;
            }
            Navigator.pop(
              context,
              AcademicCalendarEvent(
                date: _date,
                endDate:
                    (_endDate != null && _endDate!.isAfter(_date)) ? _endDate : null,
                label: label,
                category: _category,
              ),
            );
          },
          child: const Text('Done'),
        ),
      ],
    );
  }

  static String _categoryLabel(AcademicEventCategory c) => switch (c) {
        AcademicEventCategory.holiday => 'Holiday',
        AcademicEventCategory.exam => 'Exam window',
        AcademicEventCategory.deadline => 'Deadline',
        AcademicEventCategory.milestone => 'Milestone',
        AcademicEventCategory.event => 'Event',
      };
}
