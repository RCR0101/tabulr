import 'package:flutter/material.dart';
import '../models/bug_report.dart';
import '../utils/design_constants.dart';

/// Accent colour for a bug status. Hues are chosen to read well in both light
/// and dark themes; the chip tints background/border from this at low alpha.
Color bugStatusColor(BugStatus status, BuildContext context) {
  switch (status) {
    case BugStatus.pending:
      return AppDesign.warning(context);
    case BugStatus.inReview:
      return AppDesign.info(context);
    case BugStatus.devInProgress:
      return Theme.of(context).colorScheme.tertiary;
    case BugStatus.fixed:
      return AppDesign.success(context);
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
    final color = bugStatusColor(status, context);
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
