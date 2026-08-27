import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/timetable.dart';
import '../services/data/timetable_sharing_service.dart';
import '../utils/app_routes.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../services/ui/responsive_service.dart';
import 'common/app_dialog.dart';

class ShareTimetableDialog extends StatefulWidget {
  final Timetable timetable;

  const ShareTimetableDialog({super.key, required this.timetable});

  static Future<String?> show(BuildContext context, Timetable timetable) {
    if (ResponsiveService.isMobile(context)) {
      return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppDesign.glassBlur,
                sigmaY: AppDesign.glassBlur,
              ),
              child: Container(
                color: scheme.surface.withValues(alpha: 0.85),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShareTimetableDialog(timetable: timetable),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
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
  final bool _isLoading = false;
  bool _isRevoking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code = widget.timetable.shareId;
    _upload();
  }

  Future<void> _upload() async {
    if (_code == null) return;
    try {
      await TimetableSharingService().uploadShare(_code!, widget.timetable);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to upload share';
        });
      }
    }
  }

  Future<void> _revoke() async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Revoke share link?',
      message:
          'The current link will stop working. A new one will be generated.',
      confirmLabel: 'Revoke',
      isDangerous: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isRevoking = true;
      _error = null;
    });
    try {
      final newCode = await TimetableSharingService().revokeAndReshare(
        widget.timetable,
      );
      if (mounted) {
        setState(() {
          _code = newCode;
          _isRevoking = false;
        });
        ToastService.showSuccess(
          'Share link revoked. A new one has been generated.',
        );
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

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alreadyShared = widget.timetable.shareId != null;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: scheme.error));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          alreadyShared
              ? 'Your timetable is shared at the link below.'
              : 'Send this link to friends — it opens Tabulr with your timetable ready to import.',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
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
          // The link, not the raw code: a code has to be explained, pasted into
          // the right dialog and typed correctly, while a link is one tap in
          // the WhatsApp group it arrived in. The code is still what's stored,
          // and the import dialog still accepts one.
          child: SelectableText(
            _code == null ? '' : AppRoutes.shareUrl(_code!),
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
            icon:
                _isRevoking
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Icon(Icons.link_off, size: 16, color: scheme.error),
            label: Text(
              'Revoke & generate new link',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, _code),
        child: const Text('Close'),
      ),
      if (_code != null)
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: AppRoutes.shareUrl(_code!)));
            ToastService.showSuccess('Link copied to clipboard');
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy Link'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveService.isMobile(context);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.share, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Share Timetable',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context, _code),
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContent(context),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: _buildActions(context),
          ),
        ],
      );
    }

    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: AppDesign.glassBlur / 2,
        sigmaY: AppDesign.glassBlur / 2,
      ),
      child: AlertDialog(
        shape: AppDesign.dialogShape(context),
        backgroundColor: scheme.surface.withValues(alpha: 0.88),
        title: Row(
          children: [
            Icon(Icons.share, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Share Timetable'),
          ],
        ),
        content: SizedBox(width: 360, child: _buildContent(context)),
        actions: _buildActions(context),
      ),
    );
  }
}

class ImportTimetableDialog extends StatefulWidget {
  /// Pre-fills the field and looks it up straight away. Set when the app was
  /// opened on a `/s/<code>` link, so arriving from a friend's message costs
  /// no typing at all.
  final String? initialCode;

  const ImportTimetableDialog({super.key, this.initialCode});

  static Future<SharedTimetableData?> show(
    BuildContext context, {
    String? initialCode,
  }) {
    return showDialog<SharedTimetableData>(
      context: context,
      builder: (_) => ImportTimetableDialog(initialCode: initialCode),
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
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _controller.text = widget.initialCode!;
      _lookup();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    // People paste the whole link, because that is what they were given.
    final code = AppRoutes.shareCodeInText(_controller.text);
    if (code == null) return;

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
          _error = 'No timetable found for this link';
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
          _error = 'Error looking up that link';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: AppDesign.dialogShape(context),
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
              'Paste a share link (or code) from a friend to view their timetable.',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: AppDesign.inputDecoration(
                context,
                label: 'Share Link',
                hint: 'Paste link here',
                suffixIcon: IconButton(
                  icon:
                      _isLoading
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.search),
                  onPressed: _isLoading ? null : _lookup,
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By ${_preview!.ownerName} · ${_preview!.campus}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_preview!.sections.length} sections',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
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
