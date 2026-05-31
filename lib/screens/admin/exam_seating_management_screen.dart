import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/data/admin_crud_service.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/campus_service.dart';
import '../../services/ui/toast_service.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';

class ExamSeatingManagementScreen extends StatefulWidget {
  const ExamSeatingManagementScreen({super.key});

  @override
  State<ExamSeatingManagementScreen> createState() =>
      _ExamSeatingManagementScreenState();
}

Widget _examBadge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

class _ExamSeatingManagementScreenState
    extends State<ExamSeatingManagementScreen> {
  static const _campusIds = ['hyderabad', 'pilani', 'goa'];
  static const _campusLabels = {'hyderabad': 'Hyderabad', 'pilani': 'Pilani', 'goa': 'Goa'};

  final _crud = AdminCrudService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _campusId = CampusService.campusId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _switchCampus() {
    final idx = (_campusIds.indexOf(_campusId) + 1) % _campusIds.length;
    setState(() => _campusId = _campusIds[idx]);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = _searchController.text.trim();
      _entries = await _crud.fetchExamSeating(_campusId, query: q.isEmpty ? null : q);
    } catch (e) {
      ToastService.showError('Failed to load exam seating');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _showDialog({Map<String, dynamic>? existing}) async {
    final isNew = existing == null;
    final codeCtrl = TextEditingController(
        text: existing?['docId']?.toString().replaceAll('_', ' ') ?? '');
    final dateCtrl =
        TextEditingController(text: existing?['exam_date']?.toString() ?? '');

    final rooms = <Map<String, dynamic>>[];
    if (existing?['rooms'] is List) {
      for (final r in existing!['rooms'] as List) {
        rooms.add(Map<String, dynamic>.from(r as Map));
      }
    }

    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          final accent = scheme.primary;

          Widget roomCard(int idx) {
            final r = rooms[idx];
            final roomCtrl =
                TextEditingController(text: r['roomNo']?.toString() ?? '');
            final fromCtrl =
                TextEditingController(text: r['idFrom']?.toString() ?? '');
            final toCtrl =
                TextEditingController(text: r['idTo']?.toString() ?? '');
            final countCtrl = TextEditingController(
                text: r['studentCount']?.toString() ?? '');

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: AppDesign.borderRadiusSm,
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roomCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                              hintText: 'Room No',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8)),
                          onChanged: (v) => r['roomNo'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: countCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                              hintText: 'Count',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8)),
                          onChanged: (v) =>
                              r['studentCount'] = int.tryParse(v),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: scheme.error),
                        onPressed: () =>
                            setDialogState(() => rooms.removeAt(idx)),
                        padding: const EdgeInsets.only(left: 8),
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fromCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                              hintText: 'ID From',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8)),
                          onChanged: (v) => r['idFrom'] = v,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('-',
                            style: TextStyle(color: AppDesign.muted(ctx))),
                      ),
                      Expanded(
                        child: TextField(
                          controller: toCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                              hintText: 'ID To',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8)),
                          onChanged: (v) => r['idTo'] = v,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 550),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            isNew
                                ? Icons.add_rounded
                                : Icons.edit_rounded,
                            color: accent),
                        const SizedBox(width: 10),
                        Text(
                            isNew
                                ? 'Add Exam Seating'
                                : 'Edit Exam Seating',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppDesign.spacingSm),
                            child: TextField(
                              controller: codeCtrl,
                              readOnly: !isNew,
                              style: const TextStyle(fontSize: 13),
                              decoration: AppDesign.inputDecoration(ctx,
                                  label: 'Course Code',
                                  hint: 'e.g. CS F111'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppDesign.spacingSm),
                            child: TextField(
                              controller: dateCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: AppDesign.inputDecoration(ctx,
                                  label: 'Exam Date',
                                  hint: 'e.g. 07/05/2026'),
                            ),
                          ),
                          const Divider(),
                          Row(
                            children: [
                              Text('Rooms',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface)),
                              const Spacer(),
                              TextButton.icon(
                                icon: Icon(Icons.add_rounded,
                                    size: 16, color: accent),
                                label: Text('Add Room',
                                    style: TextStyle(
                                        fontSize: 12, color: accent)),
                                onPressed: () => setDialogState(() =>
                                    rooms.add({
                                      'roomNo': '',
                                      'idFrom': null,
                                      'idTo': null,
                                      'studentCount': null,
                                    })),
                              ),
                            ],
                          ),
                          for (var i = 0; i < rooms.length; i++) roomCard(i),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (!isNew)
                          AppButton(
                            label: 'Delete',
                            icon: Icons.delete_outline_rounded,
                            variant: AppButtonVariant.danger,
                            onTap: saving
                                ? null
                                : () async {
                                    final confirm = await AppDialog.confirm(
                                      context: ctx,
                                      title: 'Delete Exam Seating',
                                      message:
                                          'Delete seating for ${codeCtrl.text}?',
                                      isDangerous: true,
                                    );
                                    if (confirm && ctx.mounted) {
                                      try {
                                        await _crud.deleteExamSeating(
                                            _campusId, existing['docId']);
                                        ToastService.showSuccess('Deleted');
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        _load();
                                      } catch (e) {
                                        ToastService.showError(
                                            'Delete failed');
                                      }
                                    }
                                  },
                          ),
                        const Spacer(),
                        AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.ghost,
                          onTap: saving ? null : () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Save',
                          icon: Icons.check_rounded,
                          isLoading: saving,
                          onTap: saving
                              ? null
                              : () async {
                                  final code = codeCtrl.text.trim();
                                  if (code.isEmpty) {
                                    ToastService.showError(
                                        'Course code required');
                                    return;
                                  }
                                  setDialogState(() => saving = true);
                                  try {
                                    final docId = isNew
                                        ? code.replaceAll(
                                            RegExp(r'\s+'), '_')
                                        : existing['docId'];
                                    await _crud.saveExamSeating(_campusId, docId, {
                                      'exam_date': dateCtrl.text.trim(),
                                      'rooms': rooms,
                                      'updated_at':
                                          FieldValue.serverTimestamp(),
                                    });
                                    ToastService.showSuccess('Saved');
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _load();
                                  } catch (e) {
                                    ToastService.showError('Save failed');
                                  } finally {
                                    if (ctx.mounted) {
                                      setDialogState(() => saving = false);
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    codeCtrl.dispose();
    dateCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Exam Seating'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Exam Seating'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: () => _showDialog(),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: Row(
              children: [
                InkWell(
                  onTap: _switchCampus,
                  borderRadius: BorderRadius.circular(6),
                  child: _examBadge(
                      _campusLabels[_campusId]!, accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 14),
                    decoration: AppDesign.inputDecoration(context,
                        label: 'Search',
                        hint: 'Search by course code...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20)),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_entries.isEmpty)
            Expanded(
              child: Center(
                child: Text('No exam seating data',
                    style: TextStyle(color: AppDesign.muted(context))),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
                itemCount: _entries.length,
                itemBuilder: (_, i) {
                  final e = _entries[i];
                  final docId = e['docId']?.toString() ?? '';
                  final date = e['exam_date']?.toString() ?? '';
                  final roomCount = (e['rooms'] as List?)?.length ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppDesign.borderRadiusSm,
                      side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: InkWell(
                      borderRadius: AppDesign.borderRadiusSm,
                      onTap: () => _showDialog(existing: e),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 3),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(docId.replaceAll('_', ' '),
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.onSurface)),
                                  if (date.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(date,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppDesign.muted(
                                                  context))),
                                    ),
                                ],
                              ),
                            ),
                            _examBadge(
                                '$roomCount rooms', scheme.secondary),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
