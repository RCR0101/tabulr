import 'package:flutter/material.dart';
import '../../models/academic_record.dart';

/// Compact "you have already taken this" marker.
///
/// Shared by the minors, prerequisites and course-browser screens so the signal
/// reads identically everywhere. Renders nothing when there is no record for
/// the course — which is what keeps these lists uncluttered for students who
/// have never filled in the CGPA calculator.
class CourseRecordBadge extends StatelessWidget {
  final AcademicRecord record;
  final String courseCode;

  /// Shows the grade alongside the tick. Off in dense rows where the grade is
  /// already in its own column.
  final bool showGrade;

  const CourseRecordBadge({
    super.key,
    required this.record,
    required this.courseCode,
    this.showGrade = true,
  });

  @override
  Widget build(BuildContext context) {
    final grade = record.gradeFor(courseCode);
    if (grade == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final failed = record.hasFailed(courseCode);
    final color = failed ? scheme.error : Colors.green.shade600;

    return Tooltip(
      message: failed
          ? 'You took this and did not clear it (grade $grade)'
          : 'Already cleared with $grade',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.check_circle,
            size: 14,
            color: color,
          ),
          if (showGrade) ...[
            const SizedBox(width: 3),
            Text(
              grade,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
