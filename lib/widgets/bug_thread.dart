import 'package:flutter/material.dart';
import '../models/bug_report.dart';
import '../services/data/bug_report_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';

/// The back-and-forth conversation on a bug report, plus a composer.
///
/// Shared by the reporter's own list and the admin Bug Tracker — the only
/// difference is [asAdmin], which decides how messages are attributed and what
/// role the reply is posted under. Mount it only when the thread is actually
/// visible: it holds an open Firestore listener for as long as it lives.
class BugThread extends StatefulWidget {
  const BugThread({
    super.key,
    required this.reportId,
    required this.asAdmin,
  });

  final String reportId;

  /// True when rendered inside the admin tracker. Replies are posted as the
  /// team, and the reporter's messages are the "other" side.
  final bool asAdmin;

  @override
  State<BugThread> createState() => _BugThreadState();
}

class _BugThreadState extends State<BugThread> {
  final BugReportService _service = BugReportService();
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    final ok = await _service.sendMessage(
      reportId: widget.reportId,
      body: body,
      asAdmin: widget.asAdmin,
    );
    if (!mounted) return;

    setState(() => _sending = false);
    if (ok) {
      // Cleared only on success so a failed send doesn't lose what was typed.
      _controller.clear();
    } else {
      ToastService.showError('Could not send reply');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<BugMessage>>(
          stream: _service.messages(widget.reportId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _hint(context, 'Could not load the conversation.');
            }
            if (!snapshot.hasData) {
              return _hint(context, 'Loading conversation…');
            }

            final messages = snapshot.data!;
            if (messages.isEmpty) {
              return _hint(
                context,
                widget.asAdmin
                    ? 'No replies yet — send the first one below.'
                    : 'No replies yet. The team will respond here.',
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in messages) _bubble(context, m),
              ],
            );
          },
        ),
        const SizedBox(height: AppDesign.spacingSm),
        _composer(context),
      ],
    );
  }

  Widget _hint(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingSm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
      ),
    );
  }

  Widget _bubble(BuildContext context, BugMessage m) {
    final scheme = Theme.of(context).colorScheme;
    // "Mine" is whichever side is currently viewing, so both parties see their
    // own replies aligned right.
    final mine = m.isAdmin == widget.asAdmin;
    final label = m.isAdmin ? 'Tabulr Team' : 'Reporter';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingMd,
          vertical: AppDesign.spacingSm,
        ),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppDesign.borderRadiusMd,
          border: Border.all(
            color: (mine ? scheme.primary : scheme.outline)
                .withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine ? 'You' : label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: m.isAdmin
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 2),
            Text(m.body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              _formatDateTime(m.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            maxLength: 4999,
            textInputAction: TextInputAction.newline,
            decoration: AppDesign.inputDecoration(
              context,
              hint: widget.asAdmin
                  ? 'Reply to the reporter…'
                  : 'Add more detail or reply…',
              dense: true,
            ).copyWith(counterText: ''),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: AppDesign.spacingSm),
        IconButton.filled(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 18),
          tooltip: 'Send reply',
        ),
      ],
    );
  }

  static String _formatDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hh:$mm';
  }
}
