import 'package:flutter/material.dart';

import '../../services/data/bug_report_service.dart';
import '../../utils/design_constants.dart';

/// Count of bug reports waiting on an admin (not looked at, or the reporter
/// replied). Renders nothing at zero, or for non-admins, whose stream errors.
class BugAttentionBadge extends StatefulWidget {
  const BugAttentionBadge({super.key, this.dotOnly = false});

  /// A bare dot, for the collapsed sidebar where a number would not fit.
  final bool dotOnly;

  @override
  State<BugAttentionBadge> createState() => _BugAttentionBadgeState();
}

class _BugAttentionBadgeState extends State<BugAttentionBadge> {
  // A badge must never take the sidebar down: no Firebase means no badge.
  late final Stream<int> _count = () {
    try {
      return BugReportService().attentionCount();
    } catch (_) {
      return const Stream<int>.empty();
    }
  }();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _count,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        if (n == 0) return const SizedBox.shrink();
        final color = AppDesign.warning(context);
        if (widget.dotOnly) {
          return Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          );
        }
        return Tooltip(
          message: '$n bug report${n == 1 ? '' : 's'} need a look',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '$n',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        );
      },
    );
  }
}
