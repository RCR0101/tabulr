import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../services/core/clash_detector.dart';
import '../utils/design_constants.dart';

/// Banner listing the clashes in the current timetable.
///
/// Leads with a one-line summary so a timetable carrying an overridden exam
/// clash announces itself at a glance — the exam is months away and easy to
/// forget once the weekly grid looks clean.
class ClashWarningsWidget extends StatelessWidget {
  final List<ClashWarning> warnings;

  /// Height cap for the detail list; past this it scrolls rather than pushing
  /// the timetable grid off screen.
  static const double _maxListHeight = 180;

  /// Exam lines shown in the header before falling back to a "+N more" count;
  /// the detail list underneath carries the full set either way.
  static const int _maxExamLines = 3;

  const ClashWarningsWidget({
    super.key,
    required this.warnings,
  });

  static bool _isExam(ClashType type) =>
      type == ClashType.midSemExam ||
      type == ClashType.endSemExam ||
      type == ClashType.classAndExam;

  static bool _isClass(ClashType type) =>
      type == ClashType.regularClass || type == ClashType.classAndExam;

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 'es'}';

  /// e.g. "Exam Clash (CS F214, ECE F211) on 15 Dec". The date is omitted when
  /// the warning predates [ClashWarning.examDate] and was restored from storage.
  static String _examLine(ClashWarning warning) {
    final courses = warning.conflictingCourses.join(', ');
    final date = warning.examDate;
    return date == null
        ? 'Exam Clash ($courses)'
        : 'Exam Clash ($courses) on ${ClashDetector.formatExamDate(date)}';
  }

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();

    final examWarnings = warnings.where((w) => _isExam(w.type)).toList();
    final examCount = examWarnings.length;
    final classCount = warnings.where((w) => _isClass(w.type)).length;
    final hasError = warnings.any((w) => w.severity == ClashSeverity.error);
    final accent =
        hasError ? AppDesign.danger(context) : AppDesign.warning(context);

    final String summary;
    if (examCount > 0 && classCount > 0) {
      summary = 'This timetable has ${_count(examCount, 'exam clash')} '
          'and ${_count(classCount, 'class clash')}';
    } else if (examCount > 0) {
      summary = 'This timetable has ${_count(examCount, 'exam clash')}';
    } else {
      summary = 'This timetable has ${_count(classCount, 'class clash')}';
    }

    // mainAxisSize.min + shrinkWrap keeps this laying out correctly inside the
    // unbounded-height Card that hosts it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(hasError ? Icons.error : Icons.warning_amber_rounded,
                  color: accent, size: 20),
              const SizedBox(width: AppDesign.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    for (final w in examWarnings.take(_maxExamLines))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _examLine(w),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (examWarnings.length > _maxExamLines)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+${examWarnings.length - _maxExamLines} more below',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxListHeight),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: warnings.length,
            itemBuilder: (context, index) {
              final warning = warnings[index];
              final isError = warning.severity == ClashSeverity.error;
              final statusColor = isError
                  ? AppDesign.danger(context)
                  : AppDesign.warning(context);
              return Card(
                color: statusColor.withValues(alpha: 0.1),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isError ? Icons.error : Icons.warning,
                    color: statusColor,
                  ),
                  title: Text(warning.message),
                  subtitle: Text(
                    'Courses: ${warning.conflictingCourses.join(', ')}',
                  ),
                  trailing: Chip(
                    label: Text(
                      warning.type.toString().split('.').last,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
