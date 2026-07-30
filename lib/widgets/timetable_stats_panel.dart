import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/timetable.dart';
import '../models/timetable_stats.dart';
import '../utils/datetime_utils.dart';
import '../utils/design_constants.dart';
import 'exam_timeline_widget.dart';

/// The body of the TT Stats sheet: headline numbers, then the facts that
/// decide whether a timetable is liveable (8 AM starts, dead time between
/// classes, lunch), then the exam timeline.
class TimetableStatsPanel extends StatelessWidget {
  const TimetableStatsPanel({super.key, required this.timetable});

  final Timetable timetable;

  @override
  Widget build(BuildContext context) {
    final stats = TimetableStats.fromTimetable(timetable);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDesign.spacingMd,
              AppDesign.spacingSm, AppDesign.spacingMd, AppDesign.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Tiles(stats: stats),
              const SizedBox(height: AppDesign.spacingMd),
              _Facts(stats: stats),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(child: ExamTimelineWidget(timetable: timetable)),
      ],
    );
  }
}

/// Headline numbers, reflowing to fit the width rather than being squeezed
/// into one row.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});

  final TimetableStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = stats.isOverCreditCap;

    final tiles = <_Tile>[
      _Tile(
        icon: Icons.workspace_premium_outlined,
        value: _credits(stats.totalCredits),
        // Named after what it actually counts, and the "/cap" only appears
        // when there is a cap — credit hours have none published yet, and
        // "/25" beside a credit-hours load would be a limit nobody set.
        label: stats.creditCap == null
            ? _basisLabel(stats.creditBasis)
            : '${_basisLabel(stats.creditBasis)} (/${_credits(stats.creditCap!)})',
        // Over the cap is a real problem, not a decoration — say it in colour
        // and in the caption below.
        accent: over ? scheme.error : null,
        note: over ? 'over cap' : null,
      ),
      _Tile(
        icon: Icons.menu_book_outlined,
        value: '${stats.courseCount}',
        label: 'Courses',
      ),
      _Tile(
        icon: Icons.schedule,
        value: '${stats.totalHoursPerWeek}',
        label: 'Hours / week',
      ),
      _Tile(
        icon: Icons.event_available,
        value: '${stats.freeDayCount}',
        label: 'Free days',
      ),
      _Tile(
        icon: Icons.trending_up,
        value: '${stats.busiestDayHours}h',
        label: 'Busiest · ${getDayName(stats.busiestDay, abbreviated: true)}',
      ),
      if (stats.longestGapHours > 0 && stats.longestGapDay != null)
        _Tile(
          icon: Icons.hourglass_empty,
          value: '${stats.longestGapHours}h',
          label:
              'Longest gap · ${getDayName(stats.longestGapDay!, abbreviated: true)}',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppDesign.spacingSm;
        final columns = constraints.maxWidth >= 420 ? 4 : 3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  /// Credits are whole numbers in practice; don't print "18.0".
  static String _basisLabel(CreditBasis b) =>
      b == CreditBasis.hours ? 'Credit hours' : 'Credits';

  static String _credits(double c) =>
      c == c.roundToDouble() ? c.toInt().toString() : c.toStringAsFixed(1);
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
    this.note,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? accent;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingSm, vertical: 10),
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : accent!.withValues(alpha: 0.1),
        borderRadius: AppDesign.borderRadiusMd,
      ),
      child: Column(
        children: [
          Icon(icon, size: AppDesign.iconSizeMd, color: color),
          const SizedBox(height: AppDesign.spacingXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
            ),
          ),
          if (note != null)
            Text(
              note!,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

/// The liveability facts — each only shown when it has something to say.
class _Facts extends StatelessWidget {
  const _Facts({required this.stats});

  final TimetableStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = stats;

    String days(List<DayOfWeek> d) =>
        d.map((x) => getDayName(x, abbreviated: true)).join(', ');

    final facts = <(IconData, String, Color?)>[
      if (s.earlyStartDays.isNotEmpty)
        (
          Icons.wb_twilight,
          '8 AM start on ${days(s.earlyStartDays)}',
          s.earlyStartDays.length >= 4 ? scheme.tertiary : null,
        )
      else if (s.classDayCount > 0)
        (Icons.wb_twilight, 'No 8 AM classes', AppDesign.success(context)),
      if (s.freeDays.isNotEmpty)
        (Icons.beach_access_outlined, 'Free on ${days(s.freeDays)}', null),
      if (s.longestStreakHours >= 3 && s.longestStreakDay != null)
        (
          Icons.local_fire_department_outlined,
          '${s.longestStreakHours}h back-to-back on '
              '${getDayName(s.longestStreakDay!, abbreviated: true)}',
          s.longestStreakHours >= 5 ? scheme.error : null,
        ),
      if (s.totalGapHours > 0)
        (
          Icons.more_horiz,
          '${s.totalGapHours}h of gaps across the week',
          null,
        ),
      if ((s.hoursPerDay[DayOfWeek.S] ?? 0) > 0)
        (
          Icons.weekend_outlined,
          '${s.hoursPerDay[DayOfWeek.S]}h on Saturday',
          scheme.tertiary,
        ),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppDesign.spacingSm,
      runSpacing: AppDesign.spacingSm,
      children: [
        for (final (icon, label, accent) in facts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (accent ?? scheme.onSurface).withValues(alpha: 0.08),
              borderRadius: AppDesign.borderRadiusSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 14,
                    color: accent ??
                        scheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent ?? scheme.onSurface.withValues(alpha: 0.8),
                    fontWeight: accent == null ? null : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
