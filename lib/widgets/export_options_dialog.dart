import 'package:flutter/material.dart';
import '../models/export_options.dart';
import '../services/responsive_service.dart';

class ExportOptionsDialog extends StatefulWidget {
  final ExportOptions initialOptions;

  const ExportOptionsDialog({
    super.key,
    this.initialOptions = const ExportOptions(),
  });

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.initialOptions;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    final dialogWidth = ResponsiveService.getValue(context, 
      mobile: MediaQuery.of(context).size.width - 32,
      tablet: 500.0, 
      desktop: 400.0
    );
    
    return AlertDialog(
      insetPadding: isMobile 
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
        : null,
      title: Row(
        children: [
          Icon(
            Icons.image, 
            size: ResponsiveService.getAdaptiveIconSize(context, 24),
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          const Text('PNG Export Options'),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customize what information appears in each timetable cell:',
              style: TextStyle(
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 14), 
                fontWeight: FontWeight.w500
              ),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),
            _buildOptionTile(
              title: 'Course Code',
              subtitle: 'e.g., MATH101, CS450',
              value: _options.showCourseCode,
              onChanged: (value) => setState(() {
                _options = _options.copyWith(showCourseCode: value);
              }),
              icon: Icons.code,
            ),
            _buildOptionTile(
              title: 'Course Title',
              subtitle: 'Full course name',
              value: _options.showCourseTitle,
              onChanged: (value) => setState(() {
                _options = _options.copyWith(showCourseTitle: value);
              }),
              icon: Icons.title,
            ),
            _buildOptionTile(
              title: 'Section ID',
              subtitle: 'Section number/identifier',
              value: _options.showSectionId,
              onChanged: (value) => setState(() {
                _options = _options.copyWith(showSectionId: value);
              }),
              icon: Icons.category,
            ),
            _buildOptionTile(
              title: 'Instructor Name',
              subtitle: 'Professor/teacher name',
              value: _options.showInstructor,
              onChanged: (value) => setState(() {
                _options = _options.copyWith(showInstructor: value);
              }),
              icon: Icons.person,
            ),
            _buildOptionTile(
              title: 'Room/Location',
              subtitle: 'Classroom or venue',
              value: _options.showRoom,
              onChanged: (value) => setState(() {
                _options = _options.copyWith(showRoom: value);
              }),
              icon: Icons.location_on,
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            Container(
              padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.all(12)),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    size: ResponsiveService.getAdaptiveIconSize(context, 16),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
                  Expanded(
                    child: Text(
                      'Course code is recommended to keep enabled for clarity',
                      style: TextStyle(
                        fontSize: ResponsiveService.getAdaptiveFontSize(context, 12),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Mobile-specific action buttons
            if (isMobile) ...[
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 20)),
              Row(
                children: [
                  Expanded(
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
                  SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 12)),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        ResponsiveService.triggerMediumFeedback(context);
                        setState(() {
                          _options = const ExportOptions();
                        });
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
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ResponsiveService.triggerMediumFeedback(context);
                    Navigator.of(context).pop(_options);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: Size(
                      double.infinity,
                      ResponsiveService.getTouchTargetSize(context),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(Icons.download, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
                  label: const Text('Export PNG'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: isMobile ? null : [
        TextButton(
          onPressed: () {
            ResponsiveService.triggerSelectionFeedback(context);
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            minimumSize: Size(
              0,
              ResponsiveService.getTouchTargetSize(context),
            ),
          ),
          child: const Text('Cancel'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                ResponsiveService.triggerMediumFeedback(context);
                setState(() {
                  _options = const ExportOptions();
                });
              },
              style: TextButton.styleFrom(
                minimumSize: Size(
                  0,
                  ResponsiveService.getTouchTargetSize(context),
                ),
              ),
              child: const Text('Reset'),
            ),
            SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
            ElevatedButton.icon(
              onPressed: () {
                ResponsiveService.triggerMediumFeedback(context);
                Navigator.of(context).pop(_options);
              },
              icon: Icon(Icons.download, size: ResponsiveService.getAdaptiveIconSize(context, 16)),
              label: const Text('Export PNG'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: Size(
                  0,
                  ResponsiveService.getTouchTargetSize(context),
                ),
              ),
            ),
          ],
        ),
      ],
      actionsPadding: isMobile 
        ? EdgeInsets.zero 
        : ResponsiveService.getAdaptivePadding(
            context, 
            const EdgeInsets.fromLTRB(24, 0, 24, 24),
          ),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return CheckboxListTile(
      contentPadding: ResponsiveService.getAdaptivePadding(
        context, 
        EdgeInsets.zero,
      ),
      value: value,
      onChanged: (bool? newValue) {
        ResponsiveService.triggerSelectionFeedback(context);
        onChanged(newValue ?? false);
      },
      title: Row(
        children: [
          Icon(
            icon, 
            size: ResponsiveService.getAdaptiveIconSize(context, 18.0), 
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
          Expanded(
            child: Text(
              title, 
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: ResponsiveService.getAdaptiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(
          left: ResponsiveService.getValue(context, mobile: 30, tablet: 28, desktop: 26),
        ),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: ResponsiveService.getAdaptiveFontSize(context, 12.0),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}