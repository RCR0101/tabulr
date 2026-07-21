import 'package:flutter/material.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/profile_service.dart';
import '../utils/branch_constants.dart' as constants;

class AutoLoadCDCResult {
  final String primaryBranch;

  /// Second branch for dual-degree students, or null for a single degree.
  final String? secondaryBranch;

  /// Year-semester, e.g. `3-1`.
  final String semester;

  AutoLoadCDCResult({
    required this.primaryBranch,
    this.secondaryBranch,
    required this.semester,
  });
}

class AutoLoadCDCDialog extends StatefulWidget {
  const AutoLoadCDCDialog({super.key});

  @override
  State<AutoLoadCDCDialog> createState() => _AutoLoadCDCDialogState();
}

class _AutoLoadCDCDialogState extends State<AutoLoadCDCDialog> {
  final List<String> _branches =
      constants.branchCodeToName.keys.toList()..sort();

  // Dual-degree students run to 4-2; a single degree simply never selects those.
  final List<String> _semesters = [
    '1-1',
    '1-2',
    '2-1',
    '2-2',
    '3-1',
    '3-2',
    '4-1',
    '4-2',
  ];

  String? _selectedBranch;
  String? _selectedSecondaryBranch;
  String? _selectedSemester;

  bool get _canSubmit => _selectedBranch != null && _selectedSemester != null;

  AutoLoadCDCResult get _result => AutoLoadCDCResult(
    primaryBranch: _selectedBranch!,
    secondaryBranch: _selectedSecondaryBranch,
    semester: _selectedSemester!,
  );

  @override
  void initState() {
    super.initState();
    // Pre-select the user's saved defaults so CDC loading is one tap.
    final profile = ProfileService().cached;
    if (profile.primaryBranch != null &&
        _branches.contains(profile.primaryBranch)) {
      _selectedBranch = profile.primaryBranch;
    }
    if (profile.secondaryBranch != null &&
        _branches.contains(profile.secondaryBranch) &&
        profile.secondaryBranch != _selectedBranch) {
      _selectedSecondaryBranch = profile.secondaryBranch;
    }
    if (profile.currentSemester != null &&
        _semesters.contains(profile.currentSemester)) {
      _selectedSemester = profile.currentSemester;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.school,
            color: Theme.of(context).colorScheme.primary,
            size: ResponsiveService.getAdaptiveIconSize(context, 24),
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          Expanded(
            child: Text(
              'Auto Load CDCs',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 20),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: ResponsiveService.getValue(
          context,
          mobile: MediaQuery.sizeOf(context).width - 32,
          tablet: 400,
          desktop: 350,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select your branch and year to automatically load Core Discipline Courses (CDCs). '
                'Add a second branch if you are a dual degree student.',
                style: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                ),
              ),
              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 20),
              ),

              Text(
                'Branch *',
                style: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 8),
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedBranch,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: ResponsiveService.getAdaptivePadding(
                    context,
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                ),
                items:
                    _branches.map((branch) {
                      final name = constants.branchCodeToName[branch] ?? branch;
                      return DropdownMenuItem<String>(
                        value: branch,
                        child: Text('$branch - $name'),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  ResponsiveService.triggerSelectionFeedback(context);
                  setState(() {
                    _selectedBranch = newValue;
                    // A branch cannot be both halves of a dual degree.
                    if (_selectedSecondaryBranch == newValue) {
                      _selectedSecondaryBranch = null;
                    }
                  });
                },
                isExpanded: true,
                hint: const Text('Select your branch'),
              ),

              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 16),
              ),

              Text(
                'Second branch',
                style: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 8),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _selectedSecondaryBranch,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: ResponsiveService.getAdaptivePadding(
                    context,
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (single degree)'),
                  ),
                  ..._branches.where((branch) => branch != _selectedBranch).map(
                    (branch) {
                      final name = constants.branchCodeToName[branch] ?? branch;
                      return DropdownMenuItem<String?>(
                        value: branch,
                        child: Text('$branch - $name'),
                      );
                    },
                  ),
                ],
                onChanged: (String? newValue) {
                  ResponsiveService.triggerSelectionFeedback(context);
                  setState(() {
                    _selectedSecondaryBranch = newValue;
                  });
                },
                isExpanded: true,
              ),

              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 16),
              ),

              Text(
                'Semester *',
                style: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(
                height: ResponsiveService.getAdaptiveSpacing(context, 8),
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedSemester,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: ResponsiveService.getAdaptivePadding(
                    context,
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                ),
                items:
                    _semesters.map((semester) {
                      return DropdownMenuItem<String>(
                        value: semester,
                        child: Text('Semester $semester'),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  ResponsiveService.triggerSelectionFeedback(context);
                  setState(() {
                    _selectedSemester = newValue;
                  });
                },
                isExpanded: true,
                hint: const Text('Select your semester'),
              ),

              if (isMobile) ...[
                SizedBox(
                  height: ResponsiveService.getAdaptiveSpacing(context, 20),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      ResponsiveService.triggerSelectionFeedback(context);
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      minimumSize: Size(
                        double.infinity,
                        ResponsiveService.getTouchTargetSize(context),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(
                  height: ResponsiveService.getAdaptiveSpacing(context, 12),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _canSubmit
                            ? () {
                              ResponsiveService.triggerMediumFeedback(context);
                              Navigator.of(context).pop(_result);
                            }
                            : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      minimumSize: Size(
                        double.infinity,
                        ResponsiveService.getTouchTargetSize(context),
                      ),
                    ),
                    icon: Icon(
                      Icons.download,
                      size: ResponsiveService.getAdaptiveIconSize(context, 16),
                    ),
                    label: const Text('Load CDCs'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions:
          isMobile
              ? null
              : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      _canSubmit
                          ? () => Navigator.of(context).pop(_result)
                          : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Load CDCs'),
                ),
              ],
    );
  }
}
