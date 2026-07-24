import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../services/core/timetable_ranker.dart';
import '../utils/design_constants.dart';
import 'common/app_dialog.dart';
import 'common/app_button.dart';

class GeneratedTimetableCard extends StatelessWidget {
  final RankedTimetable ranked;
  final VoidCallback onSelect;

  /// When non-null, a compare checkbox is shown and toggling it calls this.
  final VoidCallback? onToggleCompare;
  final bool selectedForCompare;

  const GeneratedTimetableCard({
    super.key,
    required this.ranked,
    required this.onSelect,
    this.onToggleCompare,
    this.selectedForCompare = false,
  });

  GeneratedTimetable get timetable => ranked.timetable;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (onToggleCompare != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Tooltip(
                            message: 'Select to compare',
                            child: InkResponse(
                              onTap: onToggleCompare,
                              radius: 20,
                              child: Icon(
                                selectedForCompare ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 20,
                                color: selectedForCompare
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          timetable.id,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timetable.totalCredits > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${timetable.totalCredits.toStringAsFixed(1)} cr',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSelect,
                  child: const Text('Select'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Tier + fit — tappable to explain the trade-off.
            Tooltip(
              message: 'Why this rank?',
              child: InkWell(
                onTap: () => _showTradeoff(context),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tierBadge(context),
                    const SizedBox(width: 8),
                    Text(
                      'Fit ${(ranked.closeness * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                    if (ranked.weakAxes.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'relaxes ${ranked.weakAxes.map((a) => a.shortLabel).join(', ')}',
                          style: TextStyle(fontSize: 11, color: AppDesign.warning(context)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Course sections with details
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: timetable.sections.map((section) {
                final isOptional = timetable.optionalCourseCodes.contains(section.courseCode);
                final schedule = TimeSlotInfo.getFormattedSchedule(section.section.schedule);
                final instructor = section.section.instructor;
                final shortInstructor = instructor.length > 20 ? '${instructor.substring(0, 18)}...' : instructor;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOptional
                        ? Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: AppDesign.opacityLow)
                        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: AppDesign.opacityLow),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isOptional
                          ? Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.3)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${section.courseCode} - ${section.sectionId}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isOptional
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (shortInstructor.isNotEmpty)
                        Text(shortInstructor, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
                      if (schedule.isNotEmpty)
                        Text(schedule, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow))),
                    ],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Hours per day
            Text(
              'Hours per day:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
            ),
            const SizedBox(height: 4),
            Row(
              children: DayOfWeek.values.map((day) {
                final hours = timetable.hoursPerDay[day] ?? 0;
                return Expanded(
                  child: Column(
                    children: [
                      Text(day.name, style: const TextStyle(fontSize: 10)),
                      Text(
                        hours.toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: hours > 6 ? AppDesign.danger(context) : AppDesign.success(context),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            if (timetable.pros.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, color: AppDesign.success(context), size: 16),
                  const SizedBox(width: 4),
                  Text('Pros:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
                ],
              ),
              const SizedBox(height: 4),
              ...timetable.pros.map((pro) => Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 2),
                child: Text('• $pro', style: TextStyle(fontSize: 12, color: AppDesign.success(context))),
              )),
            ],

            if (timetable.cons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning, color: AppDesign.warning(context), size: 16),
                  const SizedBox(width: 4),
                  Text('Cons:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
                ],
              ),
              const SizedBox(height: 4),
              ...timetable.cons.map((con) => Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 2),
                child: Text('• $con', style: TextStyle(fontSize: 12, color: AppDesign.warning(context))),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tierBadge(BuildContext context) {
    final (label, color) = switch (ranked.tier) {
      1 => ('Best trade-off', AppDesign.success(context)),
      2 => ('Strong', Theme.of(context).colorScheme.primary),
      _ => ('Tier ${ranked.tier}', AppDesign.muted(context)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ranked.tier == 1) ...[
            Icon(Icons.star, size: 12, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Explains *why* this option ranks where it does: a per-axis satisfaction
  /// bar (relative to the best achievable in this batch), which axes it trades
  /// away, and what the tier means — replacing the opaque single number.
  void _showTradeoff(BuildContext context) {
    final axes = ranked.axisSatisfaction.keys.toList();
    AppDialog.adaptive(
      context: context,
      title: 'Why this rank?',
      icon: Icons.insights_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [_tierBadge(context), const SizedBox(width: 8), Text('Fit ${(ranked.closeness * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 6),
          Text(
            ranked.tier == 1
                ? 'A best trade-off: no other option beats it on every measure at once.'
                : 'Another option beats this on all the measures below — it\'s a compromise.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),
          if (axes.isEmpty)
            Text('All options were equal on the measures you care about.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)))
          else
            ...axes.map((a) => _axisBar(context, a, ranked.axisSatisfaction[a]!, ranked.weakAxes.contains(a))),
          const SizedBox(height: 4),
          Text(
            'Bars are relative to the best option in this batch on each measure.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
      actions: [
        AppButton(label: 'Got it', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _axisBar(BuildContext context, RankAxis axis, double value, bool weak) {
    final color = weak ? AppDesign.warning(context) : AppDesign.success(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(axis.label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
