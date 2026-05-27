import 'package:flutter/material.dart';
import '../services/ui/responsive_service.dart';
import '../utils/branch_constants.dart' as constants;

class AutoLoadCDCResult {
  final String branch;
  final String year;

  AutoLoadCDCResult({required this.branch, required this.year});
}

class AutoLoadCDCDialog extends StatefulWidget {
  const AutoLoadCDCDialog({super.key});

  @override
  State<AutoLoadCDCDialog> createState() => _AutoLoadCDCDialogState();
}

class _AutoLoadCDCDialogState extends State<AutoLoadCDCDialog> {
  final List<String> _branches = constants.branchCodeToName.keys.toList()..sort();

  final List<String> _semesters = ['1-1', '1-2', '2-1', '2-2', '3-1', '3-2'];

  String? _selectedBranch;
  String? _selectedSemester;

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
        width: ResponsiveService.getValue(context,
            mobile: MediaQuery.of(context).size.width - 32,
            tablet: 400,
            desktop: 350),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select your branch and year to automatically load Core Discipline Courses (CDCs):',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 20)),

            Text(
              'Branch *',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
              items: _branches.map((branch) {
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
                });
              },
              isExpanded: true,
              hint: const Text('Select your branch'),
            ),

            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),

            Text(
              'Semester *',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            DropdownButtonFormField<String>(
              value: _selectedSemester,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
              items: _semesters.map((semester) {
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
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 20)),
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
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_selectedBranch != null && _selectedSemester != null)
                      ? () {
                          ResponsiveService.triggerMediumFeedback(context);
                          Navigator.of(context).pop(AutoLoadCDCResult(
                            branch: _selectedBranch!,
                            year: _selectedSemester!,
                          ));
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
                  icon: Icon(Icons.download, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
                  label: const Text('Load CDCs'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: isMobile
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: (_selectedBranch != null && _selectedSemester != null)
                    ? () {
                        Navigator.of(context).pop(AutoLoadCDCResult(
                          branch: _selectedBranch!,
                          year: _selectedSemester!,
                        ));
                      }
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
