import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/data/admin_crud_service.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/campus_service.dart';
import '../../services/ui/toast_service.dart';
import '../../constants/app_constants.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/app_search_field.dart';

class ProfessorManagementScreen extends StatefulWidget {
  const ProfessorManagementScreen({super.key});

  @override
  State<ProfessorManagementScreen> createState() =>
      _ProfessorManagementScreenState();
}

Widget _profBadge(String label, Color color) {
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

class _ProfessorManagementScreenState
    extends State<ProfessorManagementScreen> {
  static const _campusIds = CampusConstants.ids;
  static const _campusLabels = CampusConstants.labels;

  final _crud = AdminCrudService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _profs = [];
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
      _profs = await _crud.fetchProfessors(_campusId, query: q.isEmpty ? null : q);
    } catch (e) {
      ToastService.showError('Failed to load professors');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _showDialog({Map<String, dynamic>? existing}) async {
    final isNew = existing == null;
    final nameCtrl =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final chamberCtrl =
        TextEditingController(text: existing?['chamber']?.toString() ?? '');
    final emailCtrl =
        TextEditingController(text: existing?['email']?.toString() ?? '');
    final contactCtrl =
        TextEditingController(text: existing?['contact']?.toString() ?? '');

    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          final accent = scheme.primary;

          Widget field(String label, TextEditingController ctrl,
              {TextInputType? keyboardType}) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: TextField(
                controller: ctrl,
                keyboardType: keyboardType,
                style: const TextStyle(fontSize: 13),
                decoration:
                    AppDesign.inputDecoration(ctx, label: label, hint: label),
              ),
            );
          }

          final scheduleCount =
              (existing?['schedule'] as List?)?.length ?? 0;

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
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
                                ? Icons.person_add_rounded
                                : Icons.edit_rounded,
                            color: accent),
                        const SizedBox(width: 10),
                        Text(
                            isNew ? 'Add Professor' : 'Edit Professor',
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
                          field('Name', nameCtrl),
                          field('Chamber', chamberCtrl),
                          field('Email', emailCtrl,
                              keyboardType: TextInputType.emailAddress),
                          field('Contact', contactCtrl,
                              keyboardType: TextInputType.phone),
                          if (!isNew && scheduleCount > 0)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.2),
                                borderRadius: AppDesign.borderRadiusSm,
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule_rounded,
                                      size: 16, color: AppDesign.muted(ctx)),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$scheduleCount schedule entries (managed via rebuild)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppDesign.muted(ctx)),
                                  ),
                                ],
                              ),
                            ),
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
                                      title: 'Delete Professor',
                                      message:
                                          'Delete ${nameCtrl.text}?',
                                      isDangerous: true,
                                    );
                                    if (confirm && ctx.mounted) {
                                      try {
                                        await _crud.deleteProfessor(
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
                                  final name = nameCtrl.text.trim();
                                  if (name.isEmpty) {
                                    ToastService.showError('Name required');
                                    return;
                                  }
                                  setDialogState(() => saving = true);
                                  try {
                                    final docId = isNew
                                        ? name
                                            .toLowerCase()
                                            .replaceAll(RegExp(r'\s+'), '_')
                                        : existing['docId'];
                                    final data = <String, dynamic>{
                                      'name': name,
                                      'chamber': chamberCtrl.text.trim().isEmpty
                                          ? 'Unavailable'
                                          : chamberCtrl.text.trim(),
                                      'updatedAt': DateTime.now()
                                          .toIso8601String(),
                                    };
                                    if (isNew) {
                                      data['id'] = docId;
                                      data['createdAt'] =
                                          DateTime.now().toIso8601String();
                                      data['schedule'] = [];
                                    }
                                    final email = emailCtrl.text.trim();
                                    final contact = contactCtrl.text.trim();
                                    if (email.isNotEmpty) {
                                      data['email'] = email;
                                    }
                                    if (contact.isNotEmpty) {
                                      data['contact'] = contact;
                                    }
                                    await _crud.saveProfessor(_campusId, docId, data);
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

    nameCtrl.dispose();
    chamberCtrl.dispose();
    emailCtrl.dispose();
    contactCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Professor Management'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Professor Management'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        onPressed: () => _showDialog(),
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
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
                  child: _profBadge(
                      _campusLabels[_campusId]!, scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    hint: 'Search by name or chamber...',
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_profs.isEmpty)
            Expanded(
              child: Center(
                child: Text('No professors found',
                    style: TextStyle(color: AppDesign.muted(context))),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
                itemCount: _profs.length,
                itemBuilder: (_, i) {
                  final p = _profs[i];
                  final name = p['name']?.toString() ?? '';
                  final chamber = p['chamber']?.toString() ?? 'Unavailable';
                  final email = p['email']?.toString() ?? '';
                  final schedCount =
                      (p['schedule'] as List?)?.length ?? 0;
                  final unavailable = chamber == 'Unavailable';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppDesign.borderRadiusSm,
                      side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: InkWell(
                      borderRadius: AppDesign.borderRadiusSm,
                      onTap: () => _showDialog(existing: p),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: unavailable
                                  ? scheme.error
                                  : AppDesign.success(context),
                              width: 3,
                            ),
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
                                  Text(name,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      _profBadge(
                                        chamber,
                                        unavailable
                                            ? scheme.error
                                            : AppDesign.success(context),
                                      ),
                                      if (email.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Icon(Icons.email_outlined,
                                            size: 14,
                                            color: AppDesign.muted(context)),
                                      ],
                                      if (schedCount > 0) ...[
                                        const SizedBox(width: 6),
                                        _profBadge('$schedCount classes',
                                            scheme.primary),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: AppDesign.muted(context)),
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
