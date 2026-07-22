import 'package:flutter/material.dart';
import '../../models/minor_programme.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/data/minor_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/course_code.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/app_search_field.dart';
import '../../widgets/common/course_picker_sheet.dart';
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
    // Block body, not an arrow: an arrow returns the assigned value, and
    // setState asserts its callback didn't hand back a Future.
    setState(() {
      _future = _service.getMinors(forceRefresh: true);
    });
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

/// Full-page editor.
///
/// Courses come from the campus course master through a multi-select picker,
/// so a code, title and unit count are never retyped by hand. Each row also
/// carries a move-to-group control, because reshuffling Core and Electives is
/// the actual work the `needsReview` queue exists for.
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
  Set<String> _catalogueCodes = const {};

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
      _groups.add(_GroupEditor(name: 'Core Courses'));
    }
    _loadCatalogue();
  }

  /// Warms the course master so existing rows can be checked against it on the
  /// first render, rather than only once the picker has been opened.
  ///
  /// Held as normalized codes rather than queried through
  /// [CoursesMasterService.get], which matches the raw string: seeded minors
  /// spell codes the Bulletin's way and would otherwise all look unknown.
  Future<void> _loadCatalogue() async {
    try {
      await CoursesMasterService().loadForCampus();
    } catch (_) {
      // Only costs the "not in catalogue" hints; editing still works.
    }
    if (!mounted) return;
    setState(() {
      _catalogueCodes = {
        for (final c in CoursesMasterService().allCourses)
          normalizeCourseCode(c.courseCode),
      };
    });
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
              courses: List.of(g.courses),
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
                      .add(_GroupEditor(name: 'Electives'))),
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
          if (g.courses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
              child: Text(
                'No courses yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            )
          else
            for (final (ci, course) in g.courses.indexed)
              _courseRow(context, g, index, ci, course),
          const SizedBox(height: AppDesign.spacingSm),
          AppButton(
            label: 'Add courses',
            icon: Icons.playlist_add,
            variant: AppButtonVariant.secondary,
            onTap: () => _addCourses(g),
          ),
        ],
      ),
    );
  }

  Widget _courseRow(
    BuildContext context,
    _GroupEditor group,
    int groupIndex,
    int courseIndex,
    MinorCourse course,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Seeded entries can name a course the current campus catalogue doesn't
    // carry. Surfaced rather than dropped — it's a data point for the review
    // pass, not something to silently discard on the next save. Stays quiet
    // until the catalogue has actually loaded, so rows don't all flash a
    // warning on first paint.
    final known = _catalogueCodes.isEmpty ||
        _catalogueCodes.contains(normalizeCourseCode(course.code));

    // Default IconButton padding is 48px each way, which made these rows twice
    // the height of their content in a list that is mostly rows.
    const density = VisualDensity(horizontal: -4, vertical: -4);
    const iconConstraints = BoxConstraints.tightFor(width: 32, height: 32);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              course.code,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              course.title.isEmpty ? '—' : course.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
          ),
          // Fixed-width from here on, so the columns line up down the list
          // instead of drifting with whichever badges a given row happens to
          // carry.
          SizedBox(
            width: 22,
            child: known
                ? null
                : Tooltip(
                    message: 'Not in this campus catalogue',
                    child: Icon(Icons.help_outline,
                        size: 15, color: scheme.tertiary),
                  ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              course.units == null ? '' : '${course.units}u',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
            ),
          ),
          const SizedBox(width: 4),
          // Moving rows between Core and Electives is the main job of the
          // review queue, so it gets a control rather than a delete-and-re-add.
          SizedBox(
            width: 32,
            child: _groups.length > 1
                ? PopupMenuButton<int>(
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                    tooltip: 'Move to group',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 160),
                    iconSize: 18,
                    onSelected: (target) => setState(() {
                      group.courses.removeAt(courseIndex);
                      _groups[target].courses.add(course);
                    }),
                    itemBuilder: (context) => [
                      for (final (i, other) in _groups.indexed)
                        if (i != groupIndex)
                          PopupMenuItem(
                            value: i,
                            child: Text(other.nameController.text.trim().isEmpty
                                ? 'Group ${i + 1}'
                                : other.nameController.text.trim()),
                          ),
                    ],
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove',
            visualDensity: density,
            constraints: iconConstraints,
            padding: EdgeInsets.zero,
            onPressed: () =>
                setState(() => group.courses.removeAt(courseIndex)),
          ),
        ],
      ),
    );
  }

  Future<void> _addCourses(_GroupEditor group) async {
    // Excludes everything already on the minor, not just this group — no
    // course may count toward a minor twice.
    final taken = {
      for (final g in _groups)
        for (final c in g.courses) c.code,
    };

    final picked = await showCoursePicker(
      context,
      alreadyChosen: taken,
      title: 'Add to ${group.nameController.text.trim()}',
    );
    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final course in picked) {
        group.courses.add(MinorCourse(
          code: course.courseCode,
          title: course.title,
          // The catalogue carries fractional credits for some courses; the
          // Bulletin states minors in whole units.
          units: course.credits > 0 ? course.credits.round() : null,
        ));
      }
    });
  }
}

/// One group's working state in the editor.
///
/// Courses are held as models rather than text: they come from the course
/// master via the picker, so there is nothing to parse and no way to mistype a
/// code, title or unit count.
class _GroupEditor {
  _GroupEditor({required String name, List<MinorCourse>? courses})
      : nameController = TextEditingController(text: name),
        courses = [...?courses];

  factory _GroupEditor.from(MinorCourseGroup group) =>
      _GroupEditor(name: group.name, courses: group.courses);

  final TextEditingController nameController;
  final List<MinorCourse> courses;

  void dispose() => nameController.dispose();
}
