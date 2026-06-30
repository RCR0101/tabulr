import 'package:flutter/material.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/data/duplicate_courses_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_search_field.dart';

/// Admin editor for course-equivalence (duplicate) mappings.
///
/// Each card is an equivalence group — a set of course codes treated as the
/// same course. Edits are serialized back to `reference/duplicate_courses`.
class DuplicateCoursesManagementScreen extends StatefulWidget {
  const DuplicateCoursesManagementScreen({super.key});

  @override
  State<DuplicateCoursesManagementScreen> createState() =>
      _DuplicateCoursesManagementScreenState();
}

class _DuplicateCoursesManagementScreenState
    extends State<DuplicateCoursesManagementScreen> {
  final _service = DuplicateCoursesService();
  final _masterService = CoursesMasterService();

  final _searchCtrl = TextEditingController();
  String _search = '';

  List<List<String>> _groups = [];
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
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(List<String> group) {
    if (_search.isEmpty) return true;
    final q = _search.toUpperCase();
    return group.any((c) =>
        c.toUpperCase().contains(q) ||
        _masterService.getTitle(c).toUpperCase().contains(q));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_masterService.isLoaded) await _masterService.loadForCampus();
      _groups = await _service.loadGroups();
    } catch (e) {
      ToastService.showError('Failed to load mappings');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    // Drop any group that ended up with < 2 codes.
    final cleaned = _groups.where((g) => g.toSet().length >= 2).toList();
    setState(() => _saving = true);
    try {
      await _service.saveGroups(cleaned);
      setState(() {
        _groups = cleaned;
        _dirty = false;
      });
      ToastService.showSuccess('Mappings saved');
    } catch (e) {
      ToastService.showError('Save failed');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _newGroup() => setState(() {
        _groups.insert(0, []);
        _dirty = true;
      });

  void _deleteGroup(int i) => setState(() {
        _groups.removeAt(i);
        _dirty = true;
      });

  void _removeCode(int groupIndex, String code) => setState(() {
        _groups[groupIndex].remove(code);
        _dirty = true;
      });

  Future<void> _addCode(int groupIndex) async {
    final code = await _pickCourse();
    if (code == null || code.isEmpty) return;
    setState(() {
      if (!_groups[groupIndex].contains(code)) {
        _groups[groupIndex].add(code);
        _groups[groupIndex].sort();
        _dirty = true;
      }
    });
  }

  Future<String?> _pickCourse() async {
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
                Text('Add course to group',
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

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Duplicate Courses'),
        body: const Center(child: Text('Admin access required')),
      );
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar:
          AppDesign.appBar(context, title: 'Duplicate Courses', actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'New group',
          onPressed: _loading ? null : _newGroup,
        ),
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppButton(
                label: 'Save',
                icon: Icons.check_rounded,
                isLoading: _saving,
                onTap: _saving ? null : _save),
          ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd,
                      AppDesign.spacingMd, AppDesign.spacingMd, AppDesign.spacingSm),
                  child: AppSearchField(
                    controller: _searchCtrl,
                    hint: 'Search a course in the mappings',
                    onChanged: (v) => setState(() => _search = v.trim()),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
                ),
                Expanded(child: _groupList(scheme)),
              ],
            ),
    );
  }

  Widget _groupList(ColorScheme scheme) {
    final visible = <int>[
      for (var i = 0; i < _groups.length; i++)
        if (_matches(_groups[i])) i
    ];

    if (_groups.isEmpty) {
      return Center(
        child: Text('No equivalence groups',
            style: TextStyle(color: AppDesign.muted(context))),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text('No group contains "$_search"',
            style: TextStyle(color: AppDesign.muted(context))),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd, 0,
          AppDesign.spacingMd, 60),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
          child: Text(
            _search.isEmpty
                ? '${_groups.length} groups'
                : '${visible.length} of ${_groups.length} groups',
            style: TextStyle(fontSize: 12, color: AppDesign.muted(context)),
          ),
        ),
        for (final i in visible) _groupCard(i, scheme),
      ],
    );
  }

  Widget _groupCard(int index, ColorScheme scheme) {
    final group = _groups[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingXs + 2),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: AppDesign.cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final code in group) _codeChip(index, code, scheme),
                _addChip(() => _addCode(index), scheme),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _deleteGroup(index),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.delete_outline_rounded,
                  size: 16, color: scheme.error.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeChip(int groupIndex, String code, ColorScheme scheme) {
    final title = _masterService.getTitle(code);
    final highlighted = _search.isNotEmpty &&
        (code.toUpperCase().contains(_search.toUpperCase()) ||
            title.toUpperCase().contains(_search.toUpperCase()));
    return Tooltip(
      message: title.isEmpty ? code : '$code — $title',
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
        decoration: BoxDecoration(
          color: highlighted
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: highlighted
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outline.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(code,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _removeCode(groupIndex, code),
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.close_rounded,
                    size: 13, color: scheme.error.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addChip(VoidCallback onTap, ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Icon(Icons.add_rounded, size: 15, color: scheme.primary),
      ),
    );
  }
}
