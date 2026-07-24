import 'package:flutter/material.dart';
import '../../models/prerequisite.dart';
import '../../repositories/prerequisites_repository.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';

/// Admin CRUD for course prerequisites (`reference/prerequisites/courses`).
class PrerequisitesManagementScreen extends StatefulWidget {
  const PrerequisitesManagementScreen({super.key});

  @override
  State<PrerequisitesManagementScreen> createState() =>
      _PrerequisitesManagementScreenState();
}

class _PrerequisitesManagementScreenState
    extends State<PrerequisitesManagementScreen> {
  final _repo = PrerequisitesRepository();
  final _masterService = CoursesMasterService();
  final _searchCtrl = TextEditingController();

  /// Courses that actually have prerequisites — the managed entries shown by
  /// default. Searching instead queries the full course master.
  List<CoursePrerequisites> _withPrereqs = [];
  Map<String, CoursePrerequisites> _prereqByCode = {};
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_masterService.isLoaded) await _masterService.loadForCampus();
      _withPrereqs = await _repo.getCoursesWithPrerequisites();
      _withPrereqs.sort((a, b) => a.courseCode.compareTo(b.courseCode));
      _prereqByCode = {for (final c in _withPrereqs) c.courseCode: c};
    } catch (e) {
      ToastService.showError('Failed to load prerequisites');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Course-master entries matching the current query (full catalog, not just
  /// timetable courses).
  List<CourseMasterEntry> _masterMatches() {
    final q = _query.toUpperCase();
    final list = _masterService.allCourses
        .where((c) =>
            c.courseCode.toUpperCase().contains(q) ||
            c.title.toUpperCase().contains(q))
        .toList()
      ..sort((a, b) => a.courseCode.compareTo(b.courseCode));
    return list.take(60).toList();
  }

  Future<void> _openEditor(CoursePrerequisites? existing) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => _PrereqEditorScreen(existing: existing)),
    );
    if (saved == true) _load();
  }

  /// Open the editor for any master course — loads its existing prereqs if it
  /// has a stored entry, otherwise seeds an empty (locked-code) entry.
  Future<void> _openEditorForCode(String code) async {
    final existing = _prereqByCode[code] ??
        await _repo.getCoursePrerequisites(code) ??
        CoursePrerequisites(
            courseCode: code, groups: const [], hasPrerequisites: false);
    await _openEditor(existing);
  }

  Future<void> _delete(CoursePrerequisites course) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Delete prerequisites?',
      message: 'Remove prerequisites for ${course.courseCode}?',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (ok) {
      try {
        await _repo.deleteCoursePrerequisites(course.courseCode);
        ToastService.showSuccess('Deleted ${course.courseCode}');
        _load();
      } catch (e) {
        ToastService.showError('Delete failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Prerequisites'),
        body: const Center(child: Text('Admin access required')),
      );
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Prerequisites', actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add prerequisites',
          onPressed: () => _openEditor(null),
        ),
      ]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: TextField(
              controller: _searchCtrl,
              decoration: AppDesign.inputDecoration(context,
                  label: 'Search any course (code or title)',
                  hint: 'e.g. CS F211',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(child: _query.isEmpty ? _managedList(scheme) : _searchList(scheme)),
        ],
      ),
    );
  }

  /// Default view: only courses that have prerequisites.
  Widget _managedList(ColorScheme scheme) {
    if (_withPrereqs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDesign.spacingLg),
          child: Text(
            'No courses have prerequisites yet.\nSearch a course or tap + to add one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppDesign.muted(context)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
      itemCount: _withPrereqs.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppDesign.spacingXs),
      itemBuilder: (_, i) {
        final c = _withPrereqs[i];
        final title = _masterService.getTitle(c.courseCode);
        return _entryTile(
          code: c.courseCode,
          subtitle: title.isEmpty
              ? '${c.groups.length} prerequisite(s)'
              : '$title · ${c.groups.length} prereq(s)',
          scheme: scheme,
          onEdit: () => _openEditor(c),
          onDelete: () => _delete(c),
        );
      },
    );
  }

  /// Search view: matches across the full course master; lets you add prereqs
  /// to any course, and edit/delete those that already have them.
  Widget _searchList(ColorScheme scheme) {
    final matches = _masterMatches();
    if (matches.isEmpty) {
      return Center(
        child: Text('No courses match "$_query"',
            style: TextStyle(color: AppDesign.muted(context))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
      itemCount: matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppDesign.spacingXs),
      itemBuilder: (_, i) {
        final m = matches[i];
        final existing = _prereqByCode[m.courseCode];
        return _entryTile(
          code: m.courseCode,
          subtitle: existing != null
              ? '${m.title} · ${existing.groups.length} prereq(s)'
              : m.title,
          scheme: scheme,
          hasEntry: existing != null,
          onTap: () => _openEditorForCode(m.courseCode),
          onEdit: () => _openEditorForCode(m.courseCode),
          onDelete: existing != null ? () => _delete(existing) : null,
        );
      },
    );
  }

  Widget _entryTile({
    required String code,
    required String subtitle,
    required ColorScheme scheme,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    bool hasEntry = true,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AppDesign.cardDecoration(context),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        onTap: onTap,
        title: Text(code,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(hasEntry ? Icons.edit_rounded : Icons.add_rounded,
                  size: 18, color: scheme.primary),
              onPressed: onEdit,
            ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: scheme.error.withValues(alpha: 0.8)),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Editor for a single course's prerequisites.
class _PrereqEditorScreen extends StatefulWidget {
  final CoursePrerequisites? existing;
  const _PrereqEditorScreen({this.existing});

  @override
  State<_PrereqEditorScreen> createState() => _PrereqEditorScreenState();
}

class _PrereqEditorScreenState extends State<_PrereqEditorScreen> {
  final _repo = PrerequisitesRepository();
  final _masterService = CoursesMasterService();

  static const _types = ['pre', 'co/pre', 'nan'];
  static const _typeLabels = {
    'pre': 'Prerequisite',
    'co/pre': 'Co-requisite',
    'nan': 'Unclear',
  };

  late final TextEditingController _codeCtrl;
  late bool _hasPrereqs;
  late List<_GroupDraft> _groups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.courseCode ?? '');
    _hasPrereqs = e?.hasPrerequisites ?? false;
    _groups = e?.groups
            .map((g) => _GroupDraft(
                  g.options.map((o) => o.courseCode).toList(),
                  g.type,
                ))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Adds a new requirement (a group starting with one option).
  Future<void> _addGroup() async {
    final code = await _pickCourse('Add requirement');
    if (code == null || code.isEmpty) return;
    setState(() => _groups.add(_GroupDraft([code.toUpperCase()], 'pre')));
  }

  /// Adds another acceptable course to an existing requirement (an OR option).
  Future<void> _addOption(int groupIndex) async {
    final code = await _pickCourse('Add alternative course');
    if (code == null || code.isEmpty) return;
    final c = code.toUpperCase();
    setState(() {
      if (!_groups[groupIndex].codes.contains(c)) _groups[groupIndex].codes.add(c);
    });
  }

  Future<String?> _pickCourse(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 240),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Autocomplete<CourseMasterEntry>(
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const [];
                    final q = v.text.toUpperCase();
                    return _masterService.allCourses
                        .where((c) =>
                            c.courseCode.toUpperCase().contains(q) ||
                            c.title.toUpperCase().contains(q))
                        .take(8);
                  },
                  displayStringForOption: (c) => c.courseCode,
                  onSelected: (c) => ctrl.text = c.courseCode,
                  optionsViewBuilder: (ctx, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: AppDesign.borderRadiusSm,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 200, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (_, i) {
                            final c = options.elementAt(i);
                            return ListTile(
                              dense: true,
                              title: Text(c.courseCode,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(c.title,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => onSelected(c),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  fieldViewBuilder: (_, textCtrl, focusNode, __) {
                    textCtrl.text = ctrl.text;
                    textCtrl.addListener(() => ctrl.text = textCtrl.text);
                    return TextField(
                      controller: textCtrl,
                      focusNode: focusNode,
                      style: const TextStyle(fontSize: 14),
                      decoration: AppDesign.inputDecoration(ctx,
                          label: 'Course Code', hint: 'e.g. CS F211'),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.ghost,
                        onTap: () => Navigator.pop(ctx)),
                    const SizedBox(width: 8),
                    AppButton(
                        label: 'Add',
                        icon: Icons.add_rounded,
                        onTap: () => Navigator.pop(ctx, ctrl.text.trim())),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      ToastService.showError('Enter a course code');
      return;
    }
    setState(() => _saving = true);
    try {
      final groups = _hasPrereqs
          ? _groups
              .where((g) => g.codes.isNotEmpty)
              .map((g) => PrerequisiteGroup(
                    g.codes
                        .map((c) => Prerequisite(courseCode: c, type: g.type))
                        .toList(),
                  ))
              .toList()
          : <PrerequisiteGroup>[];
      await _repo.saveCoursePrerequisites(CoursePrerequisites(
        courseCode: code,
        groups: groups,
        hasPrerequisites: _hasPrereqs && groups.isNotEmpty,
      ));
      ToastService.showSuccess('Saved $code');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ToastService.showError('Save failed');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;

    return Scaffold(
      appBar: AppDesign.appBar(context,
          title: isNew ? 'Add Prerequisites' : 'Edit Prerequisites'),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        children: [
          TextField(
            controller: _codeCtrl,
            enabled: isNew,
            textCapitalization: TextCapitalization.characters,
            decoration: AppDesign.inputDecoration(context,
                label: 'Course Code', hint: 'e.g. CS F211'),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Has prerequisites'),
            value: _hasPrereqs,
            onChanged: (v) => setState(() => _hasPrereqs = v),
          ),
          if (_hasPrereqs) ...[
            const SizedBox(height: AppDesign.spacingSm),
            Row(
              children: [
                Expanded(
                  child: Text('Requirements (each must be met)',
                      style: _labelStyle(scheme)),
                ),
                AppButton(
                    label: 'Add requirement',
                    icon: Icons.add_rounded,
                    variant: AppButtonVariant.ghost,
                    onTap: _addGroup),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A requirement with more than one course is satisfied by any one '
              'of them (cross-listed equivalents or alternatives).',
              style: TextStyle(fontSize: 11, color: AppDesign.muted(context)),
            ),
            const SizedBox(height: 8),
            if (_groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No requirements added',
                    style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppDesign.muted(context))),
              )
            else
              for (var i = 0; i < _groups.length; i++) _groupCard(i, scheme),
          ],
          const SizedBox(height: AppDesign.spacingLg),
          AppButton(
            label: 'Save',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onTap: _saving ? null : _save,
            expand: true,
          ),
        ],
      ),
    );
  }

  Widget _groupCard(int index, ColorScheme scheme) {
    final g = _groups[index];
    final isChoice = g.codes.length > 1;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.all(12),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Requirement ${index + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
              const Spacer(),
              // Type applies to the whole requirement.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.15)),
                ),
                child: DropdownButton<String>(
                  value: _types.contains(g.type) ? g.type : 'pre',
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface),
                  items: _types
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_typeLabels[t] ?? t)))
                      .toList(),
                  onChanged: (v) => setState(() => g.type = v ?? 'pre'),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: scheme.error.withValues(alpha: 0.8)),
                tooltip: 'Remove requirement',
                onPressed: () => setState(() => _groups.removeAt(index)),
              ),
            ],
          ),
          if (isChoice) ...[
            const SizedBox(height: 2),
            Text('Any one of:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppDesign.muted(context))),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final code in g.codes)
                Chip(
                  label: Text(code, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 15),
                  onDeleted: () => setState(() {
                    g.codes.remove(code);
                    if (g.codes.isEmpty) _groups.removeAt(index);
                  }),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 15),
                label: const Text('Alternative', style: TextStyle(fontSize: 12)),
                onPressed: () => _addOption(index),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _labelStyle(ColorScheme scheme) => TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium));
}

/// Mutable working copy of one requirement group while editing.
class _GroupDraft {
  final List<String> codes;
  String type;
  _GroupDraft(this.codes, this.type);
}
