import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../models/timetable.dart';
import '../../models/course.dart';
import '../../models/timetable_stats.dart';
import '../../utils/design_constants.dart';

class TimetableLibraryCard extends StatelessWidget {
  const TimetableLibraryCard({
    super.key,
    required this.timetable,
    required this.stats,
    required this.courseCodes,
    required this.totalCredits,
    required this.creditBasis,
    required this.accent,
    required this.index,
    required this.isCustomSort,
    required this.canDelete,
    required this.updatedLabel,
    required this.onOpen,
    required this.onInsights,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Timetable timetable;
  final TimetableStats stats;
  final List<String> courseCodes;
  final double totalCredits;
  final CreditBasis creditBasis;
  final Color accent;
  final int index;
  final bool isCustomSort;
  final bool canDelete;
  final String updatedLabel;
  final ValueChanged<BuildContext> onOpen;
  final VoidCallback onInsights;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  String _creditsLabel() {
    final value =
        totalCredits % 1 == 0
            ? totalCredits.toInt().toString()
            : totalCredits.toStringAsFixed(1);
    return '$value ${creditBasis == CreditBasis.hours ? 'ch' : 'cr'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = [
      '${courseCodes.length} ${courseCodes.length == 1 ? 'course' : 'courses'}',
      if (totalCredits > 0) _creditsLabel(),
      if (timetable.projectCount > 0)
        '${timetable.projectCount} ${timetable.projectCount == 1 ? 'project' : 'projects'}',
    ].join('  ·  ');

    final card = Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final title = _buildTitle(context, scheme);
              final preview = _buildWeekPreview(context, scheme);
              final details = _buildDetails(context, scheme, metadata);

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 16),
                    preview,
                    details,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, details],
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(width: 210, child: preview),
                  const SizedBox(width: 22),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    return KeyedSubtree(
      key: ValueKey(timetable.id),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: ClipRRect(
              borderRadius: AppDesign.borderRadiusMd,
              child: Slidable(
                startActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: .34,
                  children: [
                    SlidableAction(
                      onPressed: (_) => onRename(),
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      icon: Icons.edit_outlined,
                      label: 'Rename',
                    ),
                    SlidableAction(
                      onPressed: (_) => onDuplicate(),
                      backgroundColor: scheme.secondaryContainer,
                      foregroundColor: scheme.onSecondaryContainer,
                      icon: Icons.copy_outlined,
                      label: 'Duplicate',
                    ),
                  ],
                ),
                endActionPane:
                    canDelete
                        ? ActionPane(
                          motion: const BehindMotion(),
                          extentRatio: .22,
                          children: [
                            SlidableAction(
                              onPressed: (_) => onDelete(),
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                              icon: Icons.delete_outline,
                              label: 'Delete',
                            ),
                          ],
                        )
                        : null,
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        if (isCustomSort)
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            timetable.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Plan actions',
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
              case 'duplicate':
                onDuplicate();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
                if (canDelete)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
              ],
        ),
      ],
    );
  }

  Widget _buildDetails(
    BuildContext context,
    ColorScheme scheme,
    String metadata,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 19, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metadata,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (courseCodes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              courseCodes.join('   '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onInsights,
                  borderRadius: AppDesign.borderRadiusXs,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      stats.hasExamClusters
                          ? 'Clustered exams'
                          : stats.summaryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                updatedLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekPreview(BuildContext context, ColorScheme scheme) {
    final maxHours = stats.hoursPerDay.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Semantics(
      label: '${stats.totalHoursPerWeek} hours scheduled across the week',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < DayOfWeek.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 42,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor:
                            maxHours == 0
                                ? .08
                                : (stats.hoursPerDay[DayOfWeek.values[i]] ??
                                        0) /
                                    maxHours,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .82),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _dayLabel(DayOfWeek.values[i]),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DayOfWeek day) => switch (day) {
    DayOfWeek.M => 'M',
    DayOfWeek.T => 'T',
    DayOfWeek.W => 'W',
    DayOfWeek.Th => 'Th',
    DayOfWeek.F => 'F',
    DayOfWeek.S => 'S',
  };
}
