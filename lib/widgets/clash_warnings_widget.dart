import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../utils/design_constants.dart';

/// Banner listing the clashes in the current timetable.
///
/// Collapsed to its one-line summary by default: a timetable carrying an
/// overridden exam clash still announces itself at a glance — the exam is
/// months away and easy to forget once the weekly grid looks clean — without
/// the detail list pushing the grid off screen. Expanding shows every clash.
class ClashWarningsWidget extends StatelessWidget {
  final List<ClashWarning> warnings;

  /// Height cap for the detail list; past this it scrolls rather than pushing
  /// the timetable grid off screen.
  static const double _maxListHeight = 180;

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

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();

    final examCount = warnings.where((w) => _isExam(w.type)).length;
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

    return ExpansionTile(
      // The tile is the whole banner, not a row in a list: the default shapes
      // draw dividers above and below once expanded, and the app theme fills
      // expansion tiles with the data-table row colours. Both put a
      // square-cornered block inside the rounded card hosting this.
      shape: const Border(),
      collapsedShape: const Border(),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      iconColor: accent,
      collapsedIconColor: accent,
      leading: Icon(hasError ? Icons.error : Icons.warning_amber_rounded,
          color: accent, size: 20),
      title: Text(
        summary,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: accent,
        ),
      ),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxListHeight),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
