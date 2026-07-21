import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../utils/datetime_utils.dart';
import 'course_palette.dart';
import 'timetable_blocks.dart';

/// A chronological list of classes grouped by day.
///
/// This replaces the hours-as-columns grid on phones. That layout asks for
/// twelve columns in ~390 px of width, which no amount of density tuning
/// rescues; every mobile calendar solves the same problem with an agenda, and
/// it is the only view here that needs no horizontal scrolling at all.
class TimetableAgenda extends StatelessWidget {
  const TimetableAgenda({
    super.key,
    required this.slots,
    required this.palette,
    this.incompleteSelectionWarnings = const [],
    this.onSlotTap,
    this.onRemoveSection,
  });

  final List<TimetableSlot> slots;
  final CoursePalette palette;
  final List<String> incompleteSelectionWarnings;
  final void Function(CourseBlock block)? onSlotTap;
  final void Function(String courseCode, String sectionId)? onRemoveSection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocks = TimetableBlockMap.fromSlots(slots);
    final days = [
      for (final day in DayOfWeek.values)
        if (blocks.blocksFor(day).isNotEmpty) day,
    ];

    if (days.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No classes yet — add a section to see your week here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
          ),
        ),
      );
    }

    final today = _todayOfWeek(DateTime.now());

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final dayBlocks = [...blocks.blocksFor(day)]
          ..sort((a, b) => a.startHour.compareTo(b.startHour));
        return _DaySection(
          day: day,
          blocks: dayBlocks,
          palette: palette,
          isToday: day == today,
          incompleteSelectionWarnings: incompleteSelectionWarnings,
          onSlotTap: onSlotTap,
          onRemoveSection: onRemoveSection,
        );
      },
    );
  }

  static DayOfWeek? _todayOfWeek(DateTime now) => switch (now.weekday) {
    DateTime.monday => DayOfWeek.M,
    DateTime.tuesday => DayOfWeek.T,
    DateTime.wednesday => DayOfWeek.W,
    DateTime.thursday => DayOfWeek.Th,
    DateTime.friday => DayOfWeek.F,
    DateTime.saturday => DayOfWeek.S,
    _ => null,
  };
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.blocks,
    required this.palette,
    required this.isToday,
    required this.incompleteSelectionWarnings,
    required this.onSlotTap,
    required this.onRemoveSection,
  });

  final DayOfWeek day;
  final List<CourseBlock> blocks;
  final CoursePalette palette;
  final bool isToday;
  final List<String> incompleteSelectionWarnings;
  final void Function(CourseBlock block)? onSlotTap;
  final void Function(String courseCode, String sectionId)? onRemoveSection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Text(
                getDayName(day),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isToday ? scheme.primary : scheme.onSurface,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                blocks.length == 1 ? '1 class' : '${blocks.length} classes',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        for (final block in blocks)
          _AgendaRow(
            block: block,
            accent: palette.colorFor(block.slot.courseCode),
            hasWarning: incompleteSelectionWarnings
                .any((w) => w.startsWith(block.slot.courseCode)),
            onTap: onSlotTap == null ? null : () => onSlotTap!(block),
            onRemove: onRemoveSection == null
                ? null
                : () => onRemoveSection!(
                    block.slot.courseCode, block.slot.sectionId),
          ),
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.block,
    required this.accent,
    required this.hasWarning,
    required this.onTap,
    required this.onRemove,
  });

  final CourseBlock block;
  final Color accent;
  final bool hasWarning;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slot = block.slot;

    return Semantics(
      label:
          '${slot.courseCode} ${slot.sectionId}, ${block.timeRangeLabel}, ${slot.instructor}, ${slot.room}',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.13 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            slot.courseCode,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          slot.sectionId,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (hasWarning) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: scheme.secondary,
                          ),
                        ],
                      ],
                    ),
                    if (slot.courseTitle.isNotEmpty &&
                        slot.courseTitle != slot.courseCode) ...[
                      const SizedBox(height: 2),
                      Text(
                        slot.courseTitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.85),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        block.timeRangeLabel,
                        if (slot.room.isNotEmpty) slot.room,
                        if (slot.instructor.isNotEmpty) slot.instructor,
                      ].join('  ·  '),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove ${slot.courseCode} ${slot.sectionId}',
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
