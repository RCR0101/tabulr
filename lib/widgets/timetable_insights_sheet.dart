import 'package:flutter/material.dart';
import '../models/course.dart' show DayOfWeek;
import '../models/timetable.dart';
import '../models/timetable_stats.dart';
import '../utils/design_constants.dart';
import 'charts/exam_timeline_chart.dart';
import 'charts/weekly_load_chart.dart';

/// A bottom sheet that turns a timetable's [TimetableStats] into visuals: the
/// shape of the week (hours per day) and the exam-crunch timeline. Opened from a
/// timetable card's stats line.
class TimetableInsightsSheet extends StatelessWidget {
  const TimetableInsightsSheet({super.key, required this.timetable});

  final Timetable timetable;

  static Future<void> show(BuildContext context, Timetable timetable) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TimetableInsightsSheet(timetable: timetable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = TimetableStats.fromTimetable(timetable);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppDesign.spacingLg, 0, AppDesign.spacingLg, AppDesign.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(timetable.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Insights',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: AppDesign.spacingLg),

              // ── Weekly load ──
              _sectionTitle(context, 'Weekly load'),
              const SizedBox(height: 10),
              WeeklyLoadChart(hoursPerDay: stats.hoursPerDay),
              const SizedBox(height: 12),
              _loadFacts(context, scheme, stats),

              const SizedBox(height: AppDesign.spacingLg),
              Divider(color: scheme.outline.withValues(alpha: 0.12)),
              const SizedBox(height: AppDesign.spacingMd),

              // ── Exam crunch ──
              _sectionTitle(context, 'Exam schedule'),
              const SizedBox(height: 10),
              if (stats.hasExamClusters) ...[
                _crunchCallout(context, scheme, stats),
                const SizedBox(height: 12),
              ],
              ExamTimelineChart(
                exams: stats.allExams,
                clusters: stats.examClusters,
                campus: timetable.campus.code,
              ),
              const SizedBox(height: AppDesign.spacingSm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String s) => Text(s,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600));

  Widget _loadFacts(BuildContext context, ColorScheme scheme, TimetableStats s) {
    final facts = <(IconData, String)>[
      (Icons.schedule, '${s.totalHoursPerWeek} contact hrs/week'),
      (Icons.local_fire_department_outlined,
          'Busiest: ${_dayName(s.busiestDay)} (${s.busiestDayHours}h)'),
      if (s.freeDayCount > 0)
        (Icons.beach_access_outlined,
            '${s.freeDayCount} free day${s.freeDayCount > 1 ? 's' : ''}'
            '${s.freeDays.isNotEmpty ? ' · ${s.freeDays.map(_dayName).join(', ')}' : ''}'),
      if (s.longestGapHours > 0 && s.longestGapDay != null)
        (Icons.more_horiz,
            'Longest gap: ${s.longestGapHours}h on ${_dayName(s.longestGapDay!)}'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label) in facts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: scheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Text(label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.8))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _crunchCallout(BuildContext context, ColorScheme scheme, TimetableStats s) {
    final worst = s.examClusters
        .reduce((a, b) => a.exams.length >= b.exams.length ? a : b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Tightest stretch: ${worst.label} '
                '(${worst.exams.map((e) => e.courseCode).join(', ')})',
                style: TextStyle(
                    color: scheme.onSurface, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  static String _dayName(DayOfWeek d) => switch (d) {
        DayOfWeek.M => 'Mon',
        DayOfWeek.T => 'Tue',
        DayOfWeek.W => 'Wed',
        DayOfWeek.Th => 'Thu',
        DayOfWeek.F => 'Fri',
        DayOfWeek.S => 'Sat',
      };
}
