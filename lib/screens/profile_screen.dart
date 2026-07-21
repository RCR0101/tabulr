import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/data/profile_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/branch_constants.dart' as branch_constants;
import '../utils/design_constants.dart';
import '../widgets/common/app_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _service = ProfileService();
  final TextEditingController _idController = TextEditingController();

  static const List<String> _semesters = [
    '1-1', '1-2', '2-1', '2-2', '3-1', '3-2', '4-1', '4-2', '5-1', '5-2'
  ];

  final List<String> _branches = branch_constants.branchCodeToName.keys.toList()
    ..sort();

  String? _primaryBranch;
  String? _secondaryBranch;
  String? _semester;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _service.load();
    if (!mounted) return;
    setState(() {
      _idController.text = p.studentId;
      _primaryBranch = p.primaryBranch;
      _secondaryBranch = p.secondaryBranch;
      _semester = p.currentSemester;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _service.save(UserProfile(
      studentId: _idController.text.trim(),
      primaryBranch: _primaryBranch,
      secondaryBranch: _secondaryBranch,
      currentSemester: _semester,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ToastService.showSuccess('Profile saved');
    } else {
      ToastService.showError('Could not save. Are you signed in?');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        titleWidget: AppDesign.iconTitle(
          context,
          icon: Icons.badge_outlined,
          title: 'Profile',
          subtitle: 'Set defaults used across Tabulr',
        ),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  children: [
                    _infoBanner(context),
                    const SizedBox(height: AppDesign.spacingMd),
                    _card(context),
                    const SizedBox(height: AppDesign.spacingXl),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _infoBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: AppDesign.borderRadiusMd,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: Text(
              'These defaults pre-fill things like your exam-seating ID and '
              'CDC auto-load, so you don\'t re-enter them everywhere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingLg),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _idController,
            textCapitalization: TextCapitalization.characters,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Student ID',
              hint: 'e.g. 2023XXPSYYYYH',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          DropdownButtonFormField<String>(
            initialValue: _primaryBranch,
            isExpanded: true,
            decoration:
                AppDesign.inputDecoration(context, label: 'Primary branch'),
            items: _branchItems(),
            onChanged: (v) => setState(() => _primaryBranch = v),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          DropdownButtonFormField<String?>(
            initialValue: _secondaryBranch,
            isExpanded: true,
            decoration: AppDesign.inputDecoration(
              context,
              label: 'Secondary branch (dual degree)',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              ..._branchItems(),
            ],
            onChanged: (v) => setState(() => _secondaryBranch = v),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          DropdownButtonFormField<String>(
            initialValue: _semester,
            isExpanded: true,
            decoration:
                AppDesign.inputDecoration(context, label: 'Current semester'),
            items: _semesters
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text('Semester $s')))
                .toList(),
            onChanged: (v) => setState(() => _semester = v),
          ),
          const SizedBox(height: AppDesign.spacingLg),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Save profile',
              icon: Icons.save_outlined,
              isLoading: _saving,
              onTap: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _branchItems() {
    return _branches.map((code) {
      final name = branch_constants.branchCodeToName[code] ?? code;
      return DropdownMenuItem<String>(
        value: code,
        child: Text('$code — $name', overflow: TextOverflow.ellipsis),
      );
    }).toList();
  }
}
