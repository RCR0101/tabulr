import 'package:flutter/material.dart';
import '../../models/minor_programme.dart';
import '../../services/data/minor_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/app_search_field.dart';
import '../../widgets/common/empty_state_widget.dart';

/// Admin editor for the minor catalogue.
///
/// The seeded data came from a PDF table whose Core/Electives labels are
/// vertically centred, so group boundaries are approximate — records land with
/// `needsReview` set, and the "Needs review" filter is the working queue for
/// fixing them.
class MinorManagementScreen extends StatefulWidget {
  const MinorManagementScreen({super.key});

  @override
  State<MinorManagementScreen> createState() => _MinorManagementScreenState();
}

class _MinorManagementScreenState extends State<MinorManagementScreen> {
  final MinorService _service = MinorService();
  final TextEditingController _search = TextEditingController();

  late Future<List<MinorProgramme>> _future;
  String _query = '';
  bool _reviewOnly = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getMinors(forceRefresh: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _service.getMinors(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.workspace_premium_outlined,
          title: 'Minor Management',
          subtitle: 'Edit the published minor catalogue',
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _reload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('New minor'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: FutureBuilder<List<MinorProgramme>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data ?? const <MinorProgramme>[];
              final visible = all
                  .where((m) => m.matches(_query))
                  .where((m) => !_reviewOnly || m.needsReview)
                  .toList();

              return Column(
                children: [
                  _controls(context, all),
                  Expanded(
                    child: visible.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.inbox_outlined,
                            title: 'Nothing here',
                            subtitle: 'No minor matches these filters.',
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                                AppDesign.spacingMd,
                                0,
                                AppDesign.spacingMd,
                                96),
                            children: [
                              for (final m in visible) _row(context, m),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, List<MinorProgramme> all) {
    final pending = all.where((m) => m.needsReview).length;
    return Padding(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      child: Column(
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search minors or course codes…',
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: AppDesign.spacingSm),
          Row(
            children: [
              FilterChip(
                label: Text('Needs review ($pending)'),
                selected: _reviewOnly,
                onSelected: (v) => setState(() => _reviewOnly = v),
              ),
              const Spacer(),
              Text('${all.length} total',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, MinorProgramme m) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (m.needsReview) ...[
                      const SizedBox(width: AppDesign.spacingSm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: 0.15),
                          borderRadius: AppDesign.borderRadiusSm,
                        ),
                        child: Text(
                          'Needs review',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.tertiary),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${m.minCourses ?? '?'} courses · ${m.minUnits ?? '?'} units · '
                  '${m.courseCount} listed in ${m.groups.length} groups',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit',
            onPressed: () => _edit(m),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete',
            onPressed: () => _delete(m),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(MinorProgramme m) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Delete "${m.name}"?',
      message: 'This removes the minor from the published catalogue.',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (!ok) return;
    final done = await _service.delete(m.id);
    if (!mounted) return;
    if (done) {
      ToastService.showSuccess('Deleted');
      _reload();
    } else {
      ToastService.showError('Could not delete');
    }
  }

  Future<void> _edit(MinorProgramme? existing) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MinorEditorScreen(minor: existing),
      ),
    );
    if (saved == true) _reload();
  }
}

/// Full-page editor. Course rows are edited as plain text — one
/// `CODE | Title | units` per line — which is far quicker to correct in bulk
/// than a form with a widget per course, and matches how the seed data needs
/// fixing (moving rows between Core and Electives).
class _MinorEditorScreen extends StatefulWidget {
  const _MinorEditorScreen({this.minor});

  final MinorProgramme? minor;

  @override
  State<_MinorEditorScreen> createState() => _MinorEditorScreenState();
}

class _MinorEditorScreenState extends State<_MinorEditorScreen> {
  final MinorService _service = MinorService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _minCourses;
  late final TextEditingController _minUnits;
  late final List<_GroupEditor> _groups;
  late bool _needsReview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.minor;
    _name = TextEditingController(text: m?.name ?? '');
    _description = TextEditingController(text: m?.description ?? '');
    _minCourses = TextEditingController(text: m?.minCourses?.toString() ?? '');
    _minUnits = TextEditingController(text: m?.minUnits?.toString() ?? '');
    _needsReview = m?.needsReview ?? false;
    _groups = (m?.groups ?? const <MinorCourseGroup>[])
        .map(_GroupEditor.from)
        .toList();
    if (_groups.isEmpty) {
      _groups.add(_GroupEditor(name: 'Core Courses', courses: ''));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _minCourses.dispose();
    _minUnits.dispose();
    for (final g in _groups) {
      g.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final minor = MinorProgramme(
      id: widget.minor?.id ?? '',
      name: _name.text.trim(),
      description: _description.text.trim(),
      minCourses: int.tryParse(_minCourses.text.trim()),
      minUnits: int.tryParse(_minUnits.text.trim()),
      groups: [
        for (final g in _groups)
          if (g.nameController.text.trim().isNotEmpty)
            MinorCourseGroup(
              name: g.nameController.text.trim(),
              courses: g.parseCourses(),
            ),
      ],
      campuses: widget.minor?.campuses ?? const [],
      needsReview: _needsReview,
    );

    final ok = await _service.upsert(minor);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ToastService.showSuccess('Saved');
      Navigator.of(context).pop(true);
    } else {
      ToastService.showError('Could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: Text(widget.minor == null ? 'New minor' : 'Edit minor'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              children: [
                TextFormField(
                  controller: _name,
                  decoration:
                      AppDesign.inputDecoration(context, label: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppDesign.spacingMd),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 6,
                  decoration: AppDesign.inputDecoration(context,
                      label: 'Description'),
                ),
                const SizedBox(height: AppDesign.spacingMd),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minCourses,
                        keyboardType: TextInputType.number,
                        decoration: AppDesign.inputDecoration(context,
                            label: 'Min courses'),
                      ),
                    ),
                    const SizedBox(width: AppDesign.spacingMd),
                    Expanded(
                      child: TextFormField(
                        controller: _minUnits,
                        keyboardType: TextInputType.number,
                        decoration: AppDesign.inputDecoration(context,
                            label: 'Min units'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesign.spacingMd),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _needsReview,
                  onChanged: (v) => setState(() => _needsReview = v),
                  title: const Text('Needs review'),
                  subtitle: const Text(
                      'Turn off once the groupings have been checked against the Bulletin'),
                ),
                const Divider(),
                for (final (i, g) in _groups.indexed) ...[
                  _groupEditor(context, g, i),
                  const SizedBox(height: AppDesign.spacingMd),
                ],
                AppButton(
                  label: 'Add group',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onTap: () => setState(() => _groups
                      .add(_GroupEditor(name: 'Electives', courses: ''))),
                ),
                const SizedBox(height: AppDesign.spacingLg),
                AppButton(
                  label: 'Save',
                  icon: Icons.save,
                  isLoading: _saving,
                  expand: true,
                  onTap: _saving ? null : _save,
                ),
                const SizedBox(height: AppDesign.spacingXl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupEditor(BuildContext context, _GroupEditor g, int index) {
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: g.nameController,
                  decoration: AppDesign.inputDecoration(context,
                      label: 'Group name', dense: true),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Remove group',
                onPressed: _groups.length == 1
                    ? null
                    : () => setState(() {
                          _groups.removeAt(index).dispose();
                        }),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
          TextFormField(
            controller: g.coursesController,
            minLines: 4,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Courses',
              hint: 'CS F320 | Foundations of Data Science | 3',
              dense: true,
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs),
          Text(
            'One per line: CODE | Title | units. Units may be left off.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}

/// Backing controllers for one group in the editor.
class _GroupEditor {
  _GroupEditor({required String name, required String courses})
      : nameController = TextEditingController(text: name),
        coursesController = TextEditingController(text: courses);

  factory _GroupEditor.from(MinorCourseGroup group) => _GroupEditor(
        name: group.name,
        courses: group.courses
            .map((c) => [
                  c.code,
                  c.title,
                  if (c.units != null) '${c.units}',
                ].join(' | '))
            .join('\n'),
      );

  final TextEditingController nameController;
  final TextEditingController coursesController;

  /// Parses the textarea back into courses, skipping blank lines. A line with
  /// no separator is treated as a code-only entry rather than being dropped.
  List<MinorCourse> parseCourses() {
    final out = <MinorCourse>[];
    for (final line in coursesController.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|').map((p) => p.trim()).toList();
      out.add(MinorCourse(
        code: parts.isNotEmpty ? parts[0] : trimmed,
        title: parts.length > 1 ? parts[1] : '',
        units: parts.length > 2 ? int.tryParse(parts[2]) : null,
      ));
    }
    return out;
  }

  void dispose() {
    nameController.dispose();
    coursesController.dispose();
  }
}
