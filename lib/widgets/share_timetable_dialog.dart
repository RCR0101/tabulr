import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/timetable.dart';
import '../services/timetable_sharing_service.dart';
import '../services/toast_service.dart';
import '../utils/design_constants.dart';

class ShareTimetableDialog extends StatefulWidget {
  final Timetable timetable;

  const ShareTimetableDialog({super.key, required this.timetable});

  /// Returns the current shareId (possibly new if first share or revoked), or null if cancelled before share.
  static Future<String?> show(BuildContext context, Timetable timetable) {
    return showDialog<String>(
      context: context,
      builder: (_) => ShareTimetableDialog(timetable: timetable),
    );
  }

  @override
  State<ShareTimetableDialog> createState() => _ShareTimetableDialogState();
}

class _ShareTimetableDialogState extends State<ShareTimetableDialog> {
  String? _code;
  bool _isLoading = false;
  bool _isRevoking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shareOrReuse();
  }

  Future<void> _shareOrReuse() async {
    final existing = widget.timetable.shareId;
    if (existing != null) {
      setState(() {
        _code = existing;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final code = await TimetableSharingService().shareTimetable(widget.timetable);
      if (mounted) {
        setState(() {
          _code = code;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate share code';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: AppDesign.dialogShape,
        title: const Text('Revoke share code?'),
        content: const Text(
          'The current code will stop working. A new code will be generated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isRevoking = true;
      _error = null;
    });
    try {
      final newCode = await TimetableSharingService().revokeAndReshare(widget.timetable);
      if (mounted) {
        setState(() {
          _code = newCode;
          _isRevoking = false;
        });
        ToastService.showSuccess('Share code revoked. New code generated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to revoke';
          _isRevoking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alreadyShared = widget.timetable.shareId != null;

    return AlertDialog(
      shape: AppDesign.dialogShape,
      title: Row(
        children: [
          Icon(Icons.share, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Share Timetable'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!, style: TextStyle(color: scheme.error))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        alreadyShared
                            ? 'Your timetable is shared with the code below.'
                            : 'Share this code with friends so they can view or import your timetable.',
                        style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: AppDesign.borderRadiusMd,
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: SelectableText(
                          _code ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: scheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_code != null)
                        TextButton.icon(
                          onPressed: _isRevoking ? null : _revoke,
                          icon: _isRevoking
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.link_off, size: 16, color: scheme.error),
                          label: Text(
                            'Revoke & generate new code',
                            style: TextStyle(fontSize: 12, color: scheme.error),
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _code),
          child: const Text('Close'),
        ),
        if (_code != null)
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _code!));
              ToastService.showSuccess('Code copied to clipboard');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Code'),
          ),
      ],
    );
  }
}

class ImportTimetableDialog extends StatefulWidget {
  const ImportTimetableDialog({super.key});

  static Future<SharedTimetableData?> show(BuildContext context) {
    return showDialog<SharedTimetableData>(
      context: context,
      builder: (_) => const ImportTimetableDialog(),
    );
  }

  @override
  State<ImportTimetableDialog> createState() => _ImportTimetableDialogState();
}

class _ImportTimetableDialogState extends State<ImportTimetableDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  SharedTimetableData? _preview;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _preview = null;
    });

    try {
      final data = await TimetableSharingService().fetchSharedTimetable(code);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _error = 'No timetable found for this code';
          _isLoading = false;
        });
      } else {
        setState(() {
          _preview = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error looking up code';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: AppDesign.dialogShape,
      title: Row(
        children: [
          Icon(Icons.download, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Import Timetable'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste a share code from a friend to view their timetable.',
              style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: AppDesign.inputDecoration(
                context,
                label: 'Share Code',
                hint: 'Paste code here',
                suffixIcon: IconButton(
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  onPressed: _isLoading ? null : _lookup,
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: AppDesign.borderRadiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preview!.name,
                      style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By ${_preview!.ownerName} · ${_preview!.campus}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_preview!.sections.length} sections',
                      style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_preview != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, _preview),
            child: const Text('Import'),
          ),
      ],
    );
  }
}
