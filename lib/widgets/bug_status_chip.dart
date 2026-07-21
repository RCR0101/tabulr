import 'package:flutter/material.dart';
import '../models/bug_report.dart';

/// Accent colour for a bug status. Hues are chosen to read well in both light
/// and dark themes; the chip tints background/border from this at low alpha.
Color bugStatusColor(BugStatus status, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  switch (status) {
    case BugStatus.pending:
      return dark ? const Color(0xFFD29922) : const Color(0xFF9A6700);
    case BugStatus.inReview:
      return dark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA);
    case BugStatus.devInProgress:
      return dark ? const Color(0xFFBC8CFF) : const Color(0xFF8250DF);
    case BugStatus.fixed:
      return dark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37);
  }
}

IconData bugStatusIcon(BugStatus status) {
  switch (status) {
    case BugStatus.pending:
      return Icons.schedule;
    case BugStatus.inReview:
      return Icons.search;
    case BugStatus.devInProgress:
      return Icons.build_circle_outlined;
    case BugStatus.fixed:
      return Icons.check_circle_outline;
  }
}

/// Compact status pill used on both the user list and the admin tracker.
class BugStatusChip extends StatelessWidget {
  final BugStatus status;
  final bool small;

  const BugStatusChip({super.key, required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = bugStatusColor(status, Theme.of(context).brightness);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(bugStatusIcon(status), size: small ? 12 : 14, color: color),
          SizedBox(width: small ? 4 : 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
