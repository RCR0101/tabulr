import 'package:flutter/material.dart';
import '../models/export_options.dart';

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
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.image, size: 24),
          SizedBox(width: 8),
          Text('PNG Export Options'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customize what information appears in each timetable cell:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
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
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Course code is recommended to keep enabled for clarity',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _options = const ExportOptions();
                });
              },
              child: const Text('Reset'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_options),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export PNG'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ],
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
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (bool? newValue) => onChanged(newValue ?? false),
      title: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 26),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}