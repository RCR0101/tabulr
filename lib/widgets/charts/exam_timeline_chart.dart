import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../models/course.dart' show TimeSlotInfo;
import '../../models/timetable_stats.dart';

/// Two day-by-day strips — one for Mid-Semester exams, one for Comprehensives —
/// each spanning only its own window (from that block's first exam to its last).
/// Keeping them separate avoids a dead two-month gap between the blocks. Within
/// a strip, each calendar day is a cell; days carrying exams show a marker per
/// exam and days inside a cluster (≥2 exams within a day of each other) get a
/// red band, so a crunch reads instantly.
class ExamTimelineChart extends StatelessWidget {
  const ExamTimelineChart({
    super.key,
    required this.exams,
    required this.clusters,
    this.campus,
  });

  final List<ExamEntry> exams;
  final List<ExamCluster> clusters;
  final String? campus;

  // Indexed by DateTime.weekday - 1 (Mon=0 … Sun=6).
  static const _weekdayLetters = ['M', 'T', 'W', 'Th', 'F', 'S', 'Su'];

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (exams.isEmpty) {
      return Text('No exams scheduled for these courses yet.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)));
    }

    final mid = exams.where((e) => e.isMidSem).toList();
    final compre = exams.where((e) => !e.isMidSem).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mid.isNotEmpty)
          _block(context, scheme, 'Mid-Semester', mid, scheme.secondary),
        if (mid.isNotEmpty && compre.isNotEmpty)
          const SizedBox(height: 16),
        if (compre.isNotEmpty)
          _block(context, scheme, 'Comprehensive', compre, scheme.tertiary),
        const SizedBox(height: 10),
        _crunchLegend(context, scheme),
      ],
    );
  }

  /// One titled strip for an exam block, scaled to just that block's span.
  Widget _block(BuildContext context, ColorScheme scheme, String title,
      List<ExamEntry> blockExams, Color markerColor) {
    final first = _d(blockExams.first.date);
    final last = _d(blockExams.last.date);
    final dayCount = last.difference(first).inDays + 1;

    final byOffset = <int, List<ExamEntry>>{};
    for (final e in blockExams) {
      byOffset.putIfAbsent(_d(e.date).difference(first).inDays, () => []).add(e);
    }

    // Clusters that belong to this block (a cluster never straddles the two,
    // they're weeks apart), mapped to day offsets for the red band.
    final isMid = blockExams.first.isMidSem;
    final clusterOffsets = <int>{};
    for (final c in clusters.where((c) => c.exams.first.isMidSem == isMid)) {
      final s = _d(c.startDate).difference(first).inDays;
      final e = _d(c.endDate).difference(first).inDays;
      for (var o = s; o <= e; o++) {
        clusterOffsets.add(o);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: markerColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${blockExams.length} exam${blockExams.length > 1 ? 's' : ''} · ${_rangeLabel(first, last)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var o = 0; o < dayCount; o++)
                _dayCell(context, scheme, first.add(Duration(days: o)),
                    byOffset[o] ?? const [], clusterOffsets.contains(o),
                    markerColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, ColorScheme scheme, DateTime date,
      List<ExamEntry> dayExams, bool inCluster, Color markerColor) {
    final has = dayExams.isNotEmpty;
    return Container(
      width: 40,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: inCluster ? scheme.error.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(6),
        border: inCluster
            ? Border.all(color: scheme.error.withValues(alpha: 0.25))
            : null,
      ),
      child: Column(
        children: [
          Text(_weekdayLetters[date.weekday - 1],
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: scheme.onSurface.withValues(alpha: 0.4))),
          Text('${date.day}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: has ? FontWeight.w700 : FontWeight.w400,
                    color: has
                        ? scheme.onSurface
                        : scheme.onSurface.withValues(alpha: 0.4),
                  )),
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            child: Column(
              children: [
                for (final e in dayExams)
                  Tooltip(
                    message:
                        '${e.courseCode} · ${e.isMidSem ? 'Mid-sem' : 'Compre'} · '
                        '${TimeSlotInfo.getTimeSlotName(e.timeSlot, campus: campus)}',
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      width: 22,
                      height: 6,
                      decoration: BoxDecoration(
                        color: markerColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _crunchLegend(BuildContext context, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: scheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
          ),
        ),
        const SizedBox(width: 4),
        Text('Crunch (exams packed together)',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }

  static String _rangeLabel(DateTime a, DateTime b) {
    final mA = DayConstants.monthNames[a.month];
    final mB = DayConstants.monthNames[b.month];
    if (a.year == b.year && a.month == b.month) {
      return a.day == b.day ? '${a.day} $mA' : '${a.day}–${b.day} $mA';
    }
    return '${a.day} $mA – ${b.day} $mB';
  }
}
