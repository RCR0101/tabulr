import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/courses_master_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/branch_constants.dart' as constants;
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';

class CourseGuideManagementScreen extends StatefulWidget {
  const CourseGuideManagementScreen({super.key});

  @override
  State<CourseGuideManagementScreen> createState() =>
      _CourseGuideManagementScreenState();
}

class _CourseGuideManagementScreenState
    extends State<CourseGuideManagementScreen> {
  final _db = FirebaseFirestore.instance;
  final _masterService = CoursesMasterService();

  String? _selectedBranch;
  Map<String, List<String>> _cdcs = {};
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;
  bool _initLoading = true;

  List<CourseMasterEntry> _allCourses = [];
  List<String> _dualDegreeOverrides = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_loadMasterCourses(), _loadDualDegreeOverrides()]);
    if (mounted) setState(() => _initLoading = false);
  }

  Future<void> _loadMasterCourses() async {
    if (!_masterService.isLoaded) {
      await _masterService.loadForCampus();
    }
    _allCourses = _masterService.allCourses;
  }

  Future<void> _loadDualDegreeOverrides() async {
    try {
      final snap = await _branchesRef.get();
      _dualDegreeOverrides = snap.docs
          .map((d) => d.id)
          .where((id) => id.contains('_') && id != '_metadata')
          .toList()
        ..sort();
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>> get _branchesRef =>
      _db.collection('reference').doc('branches').collection('data');

  Future<void> _loadBranch(String branchCode) async {
    setState(() {
      _loading = true;
      _dirty = false;
    });
    try {
      final doc = await _branchesRef.doc(branchCode).get();
      final data = doc.data() ?? {};
      final rawCdcs = data['cdcs'] as Map<String, dynamic>? ?? {};
      _cdcs = rawCdcs.map(
          (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));
    } catch (e) {
      _cdcs = {};
      ToastService.showError('Failed to load branch data');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_selectedBranch == null) return;
    setState(() => _saving = true);
    try {
      await _branchesRef.doc(_selectedBranch!).set({
        'branch_code': _selectedBranch,
        'cdcs': _cdcs,
      }, SetOptions(merge: true));
      setState(() => _dirty = false);
      ToastService.showSuccess('Saved ${constants.branchCodeToName[_selectedBranch] ?? _selectedBranch}');
    } catch (e) {
      ToastService.showError('Save failed');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addCourse(String semester) {
    _showCourseCodePicker(semester);
  }

  void _removeCourse(String semester, int index) {
    setState(() {
      _cdcs[semester]!.removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _showCourseCodePicker(String semester) async {
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
              constraints:
                  const BoxConstraints(maxWidth: 400, maxHeight: 280),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Course to $semester',
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
                      optionsViewBuilder: (ctx, onSelected, options) {
                        return Align(
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
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    onTap: () => onSelected(c),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      fieldViewBuilder: (_, textCtrl, focusNode, __) {
                        textCtrl.text = codeCtrl.text;
                        textCtrl.addListener(() {
                          codeCtrl.text = textCtrl.text;
                          if (selectedName != null &&
                              textCtrl.text !=
                                  _allCourses
                                      .where(
                                          (c) => c.title == selectedName)
                                      .firstOrNull
                                      ?.courseCode) {
                            setDialogState(() => selectedName = null);
                          }
                        });
                        return TextField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 14),
                          decoration: AppDesign.inputDecoration(ctx,
                              label: 'Course Code',
                              hint: 'e.g. CS F111'),
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
                          onTap: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Add',
                          icon: Icons.add_rounded,
                          onTap: codeCtrl.text.trim().isEmpty
                              ? null
                              : () => Navigator.pop(
                                  ctx, codeCtrl.text.trim()),
                        ),
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

    if (result != null && result.isNotEmpty) {
      setState(() {
        _cdcs.putIfAbsent(semester, () => []);
        if (!_cdcs[semester]!.contains(result)) {
          _cdcs[semester]!.add(result);
          _dirty = true;
        }
      });
    }
  }

  Future<void> _showCreateDualDegreeDialog() async {
    String? msc;
    String? be;
    final mscBranches = constants.branchCodeToName.entries
        .where((e) => constants.isMscBranch(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final beBranches = constants.branchCodeToName.entries
        .where((e) => constants.isBeBranch(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Dual-Degree Override',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: AppDesign.inputDecoration(ctx,
                      label: 'MSc Branch (Primary)'),
                  items: mscBranches
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} - ${e.value}',
                              style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => msc = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: AppDesign.inputDecoration(ctx,
                      label: 'BE Branch (Secondary)'),
                  items: beBranches
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} - ${e.value}',
                              style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => be = v),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.ghost,
                      onTap: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Create',
                      icon: Icons.add_rounded,
                      onTap: msc != null && be != null
                          ? () => Navigator.pop(ctx, '${msc}_$be')
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && !_dualDegreeOverrides.contains(result)) {
      await _branchesRef.doc(result).set({
        'branch_code': result,
        'cdcs': {},
      });
      setState(() {
        _dualDegreeOverrides.add(result);
        _dualDegreeOverrides.sort();
        _selectedBranch = result;
      });
      _loadBranch(result);
      ToastService.showSuccess('Created override $result');
    }
  }

  static const _semesters = [
    '1-1', '1-2', '2-1', '2-2', '3-1', '3-2', '4-1', '4-2'
  ];

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Course Guide'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    final dropdownItems = <DropdownMenuItem<String>>[];
    final singleBranches = constants.branchCodeToName.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in singleBranches) {
      dropdownItems.add(DropdownMenuItem(
        value: e.key,
        child: Text('${e.key} - ${e.value}',
            style: const TextStyle(fontSize: 14)),
      ));
    }
    if (_dualDegreeOverrides.isNotEmpty) {
      for (final key in _dualDegreeOverrides) {
        final parts = key.split('_');
        final msc = constants.branchCodeToName[parts[0]] ?? parts[0];
        final be = constants.branchCodeToName[parts.length > 1 ? parts[1] : ''] ?? (parts.length > 1 ? parts[1] : '');
        dropdownItems.add(DropdownMenuItem(
          value: key,
          child: Text('$key - $msc + $be',
              style: TextStyle(fontSize: 14, color: scheme.tertiary)),
        ));
      }
    }

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Course Guide', actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Create dual-degree override',
          onPressed: _showCreateDualDegreeDialog,
        ),
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppButton(
              label: 'Save',
              icon: Icons.check_rounded,
              isLoading: _saving,
              onTap: _saving ? null : _save,
            ),
          ),
      ]),
      body: _initLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedBranch,
              decoration: AppDesign.inputDecoration(context,
                  label: 'Branch',
                  hint: 'Select a branch',
                  prefixIcon: const Icon(Icons.school_rounded, size: 20)),
              items: dropdownItems,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedBranch = v);
                  _loadBranch(v);
                }
              },
            ),
          ),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_selectedBranch == null)
            Expanded(
              child: Center(
                child: Text('Select a branch to edit its course structure',
                    style: TextStyle(color: AppDesign.muted(context))),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.spacingMd),
                children: [
                  for (final sem in _semesters) ...[
                    _semesterSection(sem, scheme),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _semesterSection(String semester, ColorScheme scheme) {
    final courses = _cdcs[semester] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: scheme.outline
                        .withValues(alpha: AppDesign.opacityDivider)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Year ${semester.split('-')[0]} / Sem ${semester.split('-')[1]}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${courses.length} courses',
                    style: TextStyle(
                        fontSize: 12, color: AppDesign.muted(context))),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _addCourse(semester),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 2),
                        Text('Add',
                            style: TextStyle(
                                fontSize: 12, color: scheme.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No courses',
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppDesign.muted(context))),
            )
          else
            for (var i = 0; i < courses.length; i++)
              _courseRow(semester, i, courses[i], scheme),
        ],
      ),
    );
  }

  Widget _courseRow(
      String semester, int index, String code, ColorScheme scheme) {
    final master = _masterService.get(code);
    final title = master?.title ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: scheme.outline.withValues(alpha: AppDesign.opacityDivider)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(code,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface
                        .withValues(alpha: AppDesign.opacityMedium)),
                overflow: TextOverflow.ellipsis),
          ),
          if (master != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${master.credits.toInt()}U',
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface
                          .withValues(alpha: AppDesign.opacityLow))),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _removeCourse(semester, index),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 16, color: scheme.error.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}
