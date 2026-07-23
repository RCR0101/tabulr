import 'package:flutter/material.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/branch_group_service.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/ui/toast_service.dart';
import '../../services/ui/page_leave_warning_service.dart';
import '../../utils/branch_constants.dart' as constants;
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';

/// Admin tool to manage first-year CDC groups.
///
/// A group owns the CDC lists for semesters 1-1 and 1-2; every branch assigned
/// to the group inherits those CDCs. Admins can create/rename/delete groups,
/// add or remove first-year courses, and move branches between groups. Saving
/// propagates each group's first-year CDCs to its member branches (see
/// [BranchGroupService]).
class BranchGroupManagementScreen extends StatefulWidget {
  const BranchGroupManagementScreen({super.key});

  @override
  State<BranchGroupManagementScreen> createState() =>
      _BranchGroupManagementScreenState();
}

class _BranchGroupManagementScreenState
    extends State<BranchGroupManagementScreen> {
  static const _leaveSource = 'branchGroups';

  final _service = BranchGroupService();
  final _masterService = CoursesMasterService();

  List<BranchGroup> _groups = [];
  List<CourseMasterEntry> _allCourses = [];
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
    // Never leave a stale unload prompt armed on the screens that come after.
    PageLeaveWarningService().clear(_leaveSource);
    super.dispose();
  }

  /// Single choke point for dirty state: keeps the Save button and the web
  /// refresh/close prompt in lockstep so neither can be armed without the other.
  void _setDirty(bool value) {
    if (_dirty != value) setState(() => _dirty = value);
    PageLeaveWarningService().setUnsaved(_leaveSource, value);
  }

  Future<bool> _confirmDiscard() => AppDialog.confirm(
        context: context,
        title: 'Unsaved Changes',
        message:
            'You have unsaved group changes that will be lost. Leave anyway?',
        confirmLabel: 'Leave',
        cancelLabel: 'Stay',
        isDangerous: true,
      );

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_masterService.isLoaded) await _masterService.loadForCampus();
      _allCourses = _masterService.allCourses;
      _groups = await _service.loadGroups();
    } catch (e) {
      ToastService.showError('Failed to load groups');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveGroups(_groups);
      _setDirty(false);
      ToastService.showSuccess('Groups saved');
    } catch (e) {
      ToastService.showError('Save failed');
    }
    if (mounted) setState(() => _saving = false);
  }

  // ── Group CRUD ────────────────────────────────────────────────────────────

  Future<void> _createGroup() async {
    final name = await _promptName('New Group', '');
    if (name == null) return;
    setState(() {
      _groups.add(BranchGroup(
        id: 'g${DateTime.now().millisecondsSinceEpoch}',
        name: name.isEmpty ? 'Group ${_groups.length + 1}' : name,
        sem11: [],
        sem12: [],
        branches: [],
      ));
    });
    _setDirty(true);
  }

  Future<void> _renameGroup(BranchGroup group) async {
    final name = await _promptName('Rename Group', group.name);
    if (name == null || name.isEmpty) return;
    setState(() => group.name = name);
    _setDirty(true);
  }

  Future<void> _deleteGroup(BranchGroup group) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Delete group?',
      message: '"${group.name}" will be removed. Its ${group.branches.length} '
          'branch(es) become ungrouped. Branch CDCs already saved are not '
          'cleared.',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (ok) {
      setState(() => _groups.remove(group));
      _setDirty(true);
    }
  }

  Future<String?> _promptName(String title, String initial) async {
    final result = await AppDialog.input(
      context: context,
      title: title,
      initialValue: initial,
      hint: 'Group name',
    );
    return result?.trim();
  }

  // ── CDC editing ───────────────────────────────────────────────────────────

  void _removeCourse(List<String> list, int index) {
    setState(() => list.removeAt(index));
    _setDirty(true);
  }

  Future<void> _addCourse(BranchGroup group, String sem, List<String> list) async {
    final code = await _showCoursePicker(group.name, sem);
    if (code == null || code.isEmpty) return;
    if (list.contains(code)) return;
    setState(() => list.add(code));
    _setDirty(true);
  }

  Future<String?> _showCoursePicker(String groupName, String sem) async {
    final codeCtrl = TextEditingController();
    String? selectedName;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add course to $groupName · Sem $sem',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Autocomplete<CourseMasterEntry>(
                      optionsBuilder: (v) {
                        if (v.text.isEmpty) return const [];
                        final q = v.text.toUpperCase();
                        return _allCourses
                            .where((c) =>
                                c.courseCode.toUpperCase().contains(q) ||
                                c.title.toUpperCase().contains(q))
                            .take(8);
                      },
                      displayStringForOption: (c) => c.courseCode,
                      onSelected: (c) {
                        codeCtrl.text = c.courseCode;
                        setDialogState(() => selectedName = c.title);
                      },
                      optionsViewBuilder: (ctx, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: AppDesign.borderRadiusSm,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 200, maxWidth: 360),
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
                        textCtrl.text = codeCtrl.text;
                        textCtrl.addListener(() => codeCtrl.text = textCtrl.text);
                        return TextField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 14),
                          decoration: AppDesign.inputDecoration(ctx,
                              label: 'Course Code', hint: 'e.g. CS F111'),
                        );
                      },
                    ),
                    if (selectedName != null) ...[
                      const SizedBox(height: 8),
                      Text(selectedName!,
                          style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface
                                  .withValues(alpha: AppDesign.opacityMedium))),
                    ],
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
                            onTap: () =>
                                Navigator.pop(ctx, codeCtrl.text.trim())),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    codeCtrl.dispose();
    return result;
  }

  // ── Branch assignment ───────────────────────────────────────────────────────

  /// Assign [code] to [target], removing it from any other group first.
  void _assignBranch(String code, BranchGroup target) {
    setState(() {
      for (final g in _groups) {
        g.branches.remove(code);
      }
      target.branches.add(code);
      target.branches.sort();
    });
    _setDirty(true);
  }

  void _removeBranch(BranchGroup group, String code) {
    setState(() => group.branches.remove(code));
    _setDirty(true);
  }

  Future<void> _showAddBranchDialog(BranchGroup target) async {
    // Any coded branch not already in this group can be added (moved).
    final candidates = constants.branchCodeToName.keys
        .where((c) => !target.branches.contains(c))
        .toList()
      ..sort();
    if (candidates.isEmpty) {
      ToastService.showInfo('All branches are already in this group');
      return;
    }

    final scheme = Theme.of(context).colorScheme;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add branch to ${target.name}',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final code = candidates[i];
                      final current = _groupOf(code);
                      return ListTile(
                        dense: true,
                        title: Text(
                            '$code · ${constants.branchCodeToName[code]}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: current != null
                            ? Text('Currently in ${current.name}',
                                style: TextStyle(
                                    fontSize: 11, color: scheme.tertiary))
                            : Text('Ungrouped',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurface.withValues(
                                        alpha: AppDesign.opacityLow))),
                        onTap: () => Navigator.pop(ctx, code),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.ghost,
                      onTap: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (picked != null) _assignBranch(picked, target);
  }

  BranchGroup? _groupOf(String code) {
    for (final g in _groups) {
      if (g.branches.contains(code)) return g;
    }
    return null;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Branch Groups'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && navigator.canPop()) navigator.pop();
      },
      child: Scaffold(
      appBar: AppDesign.appBar(context, title: 'Branch Groups', actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'New group',
          onPressed: _loading ? null : _createGroup,
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
          : ListView(
              padding: const EdgeInsets.all(AppDesign.spacingMd),
              children: [
                _infoBanner(scheme),
                for (final g in _groups) _groupCard(g, scheme),
                _ungroupedCard(scheme),
                const SizedBox(height: 60),
              ],
            ),
      ),
    );
  }

  Widget _infoBanner(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      padding: const EdgeInsets.all(AppDesign.spacingSm + 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              'Groups segment the first-year CDCs (Sem 1-1 & 1-2). Edit a '
              'group\'s courses or move branches between groups, then Save — '
              'each branch inherits its group\'s CDCs.',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      scheme.onSurface.withValues(alpha: AppDesign.opacityHigh)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(BranchGroup group, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: scheme.outline
                        .withValues(alpha: AppDesign.opacityDivider)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.workspaces_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(group.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                ),
                Text('${group.branches.length} branches',
                    style: TextStyle(
                        fontSize: 12, color: AppDesign.muted(context))),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      size: 18, color: AppDesign.muted(context)),
                  onSelected: (v) {
                    if (v == 'rename') _renameGroup(group);
                    if (v == 'delete') _deleteGroup(group);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
          _cdcSection(group, '1-1', group.sem11, scheme),
          _cdcSection(group, '1-2', group.sem12, scheme),
          // Branches
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Branches', scheme),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final code in group.branches)
                      _removableChip(
                        label: code,
                        sub: constants.branchCodeToName[code],
                        scheme: scheme,
                        onRemove: () => _removeBranch(group, code),
                      ),
                    _addChip('Add branch', scheme,
                        () => _showAddBranchDialog(group)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cdcSection(
      BranchGroup group, String sem, List<String> codes, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Semester $sem CDCs', scheme),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < codes.length; i++)
                _removableChip(
                  label: codes[i],
                  sub: _masterService.get(codes[i])?.title,
                  scheme: scheme,
                  onRemove: () => _removeCourse(codes, i),
                ),
              _addChip('Add course', scheme,
                  () => _addCourse(group, sem, codes)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ungroupedCard(ColorScheme scheme) {
    final ungrouped = _service.ungroupedBranches(_groups);
    if (ungrouped.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingMd),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ungrouped branches',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.error)),
          const SizedBox(height: 4),
          Text('These branches aren\'t in any group. Use "Add branch" in a '
              'group to assign them.',
              style: TextStyle(
                  fontSize: 11, color: AppDesign.muted(context))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in ungrouped)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$code · ${constants.branchCodeToName[code]}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme scheme) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
      );

  Widget _removableChip({
    required String label,
    String? sub,
    required ColorScheme scheme,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(sub,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface
                          .withValues(alpha: AppDesign.opacityMedium))),
            ),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.close_rounded,
                  size: 15, color: scheme.error.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addChip(String label, ColorScheme scheme, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: scheme.primary),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}
