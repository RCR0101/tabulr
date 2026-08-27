import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/cdc_slot.dart';
import '../services/data/branch_structure_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/profile_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/secure_logger.dart';
import '../utils/branch_constants.dart' as constants;
import '../utils/design_constants.dart';

class AutoLoadCDCResult {
  final String primaryBranch;
  final String? secondaryBranch;
  final String semester;
  final Set<String> chosen;

  AutoLoadCDCResult({
    required this.primaryBranch,
    this.secondaryBranch,
    required this.semester,
    this.chosen = const {},
  });
}

/// Reusable branch and semester picker used inline and inside a dialog.
class AutoLoadCDCSelector extends StatefulWidget {
  const AutoLoadCDCSelector({
    super.key,
    required this.onSelected,
    this.semesters,
    this.initialValue,
    this.onCancel,
    this.actionLabel = 'Load CDCs',
  });

  final List<String>? semesters;
  final AutoLoadCDCResult? initialValue;
  final ValueChanged<AutoLoadCDCResult> onSelected;
  final VoidCallback? onCancel;
  final String actionLabel;

  @override
  State<AutoLoadCDCSelector> createState() => _AutoLoadCDCSelectorState();
}

class _AutoLoadCDCSelectorState extends State<AutoLoadCDCSelector> {
  final List<String> _branches = constants.branchCodeToName.keys.toList()
    ..sort();

  late final List<String> _semesters =
      widget.semesters ?? SemesterConstants.yearsOneToFour;
  String? _selectedBranch;
  String? _selectedSecondaryBranch;
  String? _selectedSemester;
  List<CdcSlot>? _choices;
  final Map<int, String> _picks = {};
  bool _resolving = false;

  bool get _canSubmit => _selectedBranch != null && _selectedSemester != null;
  bool get _canAdvance =>
      !_resolving &&
      (_choices == null ? _canSubmit : _picks.length == _choices!.length);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    if (initial != null) {
      _selectedBranch = initial.primaryBranch;
      _selectedSecondaryBranch = initial.secondaryBranch;
      _selectedSemester = initial.semester;
      return;
    }

    // Profile access is best-effort because previews and tests may not boot Firebase.
    try {
      final profile = ProfileService().cached;
      if (_branches.contains(profile.primaryBranch)) {
        _selectedBranch = profile.primaryBranch;
      }
      if (_branches.contains(profile.secondaryBranch) &&
          profile.secondaryBranch != _selectedBranch) {
        _selectedSecondaryBranch = profile.secondaryBranch;
      }
      if (_semesters.contains(profile.currentSemester)) {
        _selectedSemester = profile.currentSemester;
      }
    } catch (_) {
      // Empty fields are valid when no profile service is available.
    }
  }

  AutoLoadCDCResult get _result => AutoLoadCDCResult(
    primaryBranch: _selectedBranch!,
    secondaryBranch: _selectedSecondaryBranch,
    semester: _selectedSemester!,
    chosen: _picks.values.toSet(),
  );

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _resolving = true);

    List<CdcSlot> slots;
    try {
      slots = await BranchStructureService().getCoreCourseSlots(
        _selectedSemester!,
        _selectedBranch!,
        null,
        _selectedSecondaryBranch,
      );
    } catch (error) {
      SecureLogger.warning('AUTO_LOAD_CDC', 'Could not resolve optional CDCs', {
        'error': error.toString(),
      });
      slots = const [];
    }
    if (!mounted) return;

    final choices = [
      for (final slot in slots)
        if (slot.isChoice) slot,
    ];
    if (choices.isEmpty) {
      setState(() => _resolving = false);
      widget.onSelected(_result);
      return;
    }

    final previous = widget.initialValue?.chosen ?? const <String>{};
    setState(() {
      _choices = choices;
      _picks.clear();
      for (var index = 0; index < choices.length; index++) {
        for (final option in choices[index].options) {
          if (previous.contains(option)) {
            _picks[index] = option;
            break;
          }
        }
      }
      _resolving = false;
    });
  }

  void _advance() {
    if (_choices == null) {
      _submit();
    } else {
      widget.onSelected(_result);
    }
  }

  void _back() {
    if (_choices == null) {
      widget.onCancel?.call();
      return;
    }
    setState(() {
      _choices = null;
      _picks.clear();
    });
  }

  void _resetChoices() {
    _choices = null;
    _picks.clear();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : AppDesign.animDurationNormal,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: _choices == null
              ? _degreeStep(key: const ValueKey('degree-step'))
              : _choiceStep(key: const ValueKey('choice-step')),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final backButton = widget.onCancel != null || _choices != null
                ? OutlinedButton(
                    onPressed: _back,
                    child: Text(_choices == null ? 'Cancel' : 'Back'),
                  )
                : null;
            final action = FilledButton.icon(
              onPressed: _canAdvance ? _advance : null,
              icon: _resolving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                _choices == null ? widget.actionLabel : 'Use choices',
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (backButton != null) backButton,
                  if (backButton != null) const SizedBox(height: 10),
                  action,
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (backButton != null) backButton,
                if (backButton != null) const SizedBox(width: 10),
                action,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _degreeStep({required Key key}) => LayoutBuilder(
    key: key,
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 620;
      final branch = _field(
        label: 'Branch',
        child: DropdownButtonFormField<String>(
          initialValue: _selectedBranch,
          decoration: const InputDecoration(
            hintText: 'Select your branch',
            prefixIcon: Icon(Icons.account_tree_outlined),
          ),
          items: [
            for (final branch in _branches)
              DropdownMenuItem(
                value: branch,
                child: Text(
                  '$branch - ${constants.branchCodeToName[branch] ?? branch}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            ResponsiveService.triggerSelectionFeedback(context);
            setState(() {
              _selectedBranch = value;
              if (_selectedSecondaryBranch == value) {
                _selectedSecondaryBranch = null;
              }
              _resetChoices();
            });
          },
          isExpanded: true,
        ),
      );
      final semester = _field(
        label: 'Semester',
        child: DropdownButtonFormField<String>(
          initialValue: _selectedSemester,
          decoration: const InputDecoration(
            hintText: 'Select semester',
            prefixIcon: Icon(Icons.calendar_today_outlined),
          ),
          items: [
            for (final semester in _semesters)
              DropdownMenuItem(
                value: semester,
                child: Text('Semester $semester'),
              ),
          ],
          onChanged: (value) {
            ResponsiveService.triggerSelectionFeedback(context);
            setState(() {
              _selectedSemester = value;
              _resetChoices();
            });
          },
          isExpanded: true,
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select your degree and semester. Tabulr will resolve the published Core Discipline Course package for you.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: branch),
                const SizedBox(width: 16),
                Expanded(child: semester),
              ],
            )
          else ...[
            branch,
            const SizedBox(height: 16),
            semester,
          ],
          const SizedBox(height: 16),
          _field(
            label: 'Second branch (optional)',
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedSecondaryBranch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.call_split_rounded),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None - single degree'),
                ),
                for (final branch in _branches.where(
                  (item) => item != _selectedBranch,
                ))
                  DropdownMenuItem<String?>(
                    value: branch,
                    child: Text(
                      '$branch - ${constants.branchCodeToName[branch] ?? branch}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                ResponsiveService.triggerSelectionFeedback(context);
                setState(() {
                  _selectedSecondaryBranch = value;
                  _resetChoices();
                });
              },
              isExpanded: true,
            ),
          ),
        ],
      );
    },
  );

  Widget _field({required String label, required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _choiceStep({required Key key}) {
    final scheme = Theme.of(context).colorScheme;
    final choices = _choices!;
    final master = CoursesMasterService();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          choices.length == 1
              ? 'One CDC has alternatives. Pick the course you are taking.'
              : '${choices.length} CDCs have alternatives. Pick one course from each group.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < choices.length; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _picks.containsKey(index)
                    ? scheme.primary.withValues(alpha: 0.5)
                    : scheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in choices[index].options)
                  RadioListTile<String>(
                    value: option,
                    // ignore: deprecated_member_use
                    groupValue: _picks[index],
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      ResponsiveService.triggerSelectionFeedback(context);
                      setState(() => _picks[index] = value!);
                    },
                    dense: true,
                    title: Text(
                      option,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(master.getTitle(option)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class AutoLoadCDCDialog extends StatelessWidget {
  const AutoLoadCDCDialog({super.key, this.semesters, this.initialValue});

  final List<String>? semesters;
  final AutoLoadCDCResult? initialValue;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(
          Icons.school_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        const Expanded(child: Text('Auto Load CDCs')),
      ],
    ),
    content: SizedBox(
      width: ResponsiveService.getValue(
        context,
        mobile: MediaQuery.sizeOf(context).width - 32,
        tablet: 440,
        desktop: 460,
      ),
      child: SingleChildScrollView(
        child: AutoLoadCDCSelector(
          semesters: semesters,
          initialValue: initialValue,
          onCancel: () => Navigator.pop(context),
          onSelected: (result) => Navigator.pop(context, result),
        ),
      ),
    ),
  );
}
