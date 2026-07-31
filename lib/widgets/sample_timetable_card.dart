import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../models/timetable_constraints.dart';
import '../utils/design_constants.dart';
import 'timetable_widget.dart';

/// One sample timetable: what it is, what its week looks like, and the button
/// that takes it.
///
/// The grid is the point. A list of section ids is not something a student can
/// judge a timetable by, and these are shown to people who have never built
/// one — so the card carries a real, if small, week.
class SampleTimetableCard extends StatelessWidget {
  const SampleTimetableCard({
    super.key,
    required this.generated,
    required this.slots,
    required this.onUse,
  });

  final GeneratedTimetable generated;

  /// The week to draw, already resolved against a catalog by the caller.
  final List<TimetableSlot> slots;

  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        generated.id,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // No credit total: a sample is the published package,
                        // so its weight is not a choice the student is making
                        // here, and the two bases made it a number to explain.
                        '${generated.sections.length} sections',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface
                              .withValues(alpha: AppDesign.opacityMedium),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onUse,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Use this'),
                ),
              ],
            ),
          ),
          if (generated.pros.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Three at most: the strip is a glance, not the ranking.
                    for (final pro in generated.pros.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          pro,
                          style: TextStyle(fontSize: 11, color: scheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: TimetableWidget(
              timetableSlots: slots,
              size: TimetableSize.compact,
              incompleteSelectionWarnings: const [],
              readOnly: true,
            ),
          ),
        ],
      ),
    );
  }
}
