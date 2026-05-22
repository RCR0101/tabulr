import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../utils/design_constants.dart';

class GeneratedTimetableCard extends StatelessWidget {
  final GeneratedTimetable timetable;
  final VoidCallback onSelect;

  const GeneratedTimetableCard({
    super.key,
    required this.timetable,
    required this.onSelect,
  });

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
                Row(
                  children: [
                    Text(
                      timetable.id,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getScoreColor(context, timetable.score),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Score: ${timetable.score.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: onSelect,
                      child: const Text('Select'),
                    ),
                  ],
                ),
              ],
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
                      Text(
                        day.name,
                        style: const TextStyle(fontSize: 10),
                      ),
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
            
            // Pros and cons
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
                child: Text(
                  '• $pro',
                  style: TextStyle(fontSize: 12, color: AppDesign.success(context)),
                ),
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
                child: Text(
                  '• $con',
                  style: TextStyle(fontSize: 12, color: AppDesign.warning(context)),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(BuildContext context, double score) {
    if (score >= 80) return AppDesign.success(context);
    if (score >= 60) return AppDesign.warning(context);
    return AppDesign.danger(context);
  }
}