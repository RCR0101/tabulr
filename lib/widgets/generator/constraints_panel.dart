import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/timetable_constraints.dart';
import '../../services/core/timetable_generator_controller.dart';
import '../../services/data/campus_service.dart';
import '../../utils/datetime_utils.dart';
import '../../services/ui/responsive_service.dart';
import '../../utils/design_constants.dart';
import '../common/app_tappable.dart';
import '../common/app_dropdown.dart';
import 'constraint_controls.dart';
import 'instructor_avoidance_dialog.dart';
import 'instructor_ranking_dialog.dart';
import 'lab_avoidance_dialog.dart';
import 'time_avoidance_dialog.dart';

/// Every "shape the week" preference the generator understands, in one panel.
///
/// Extracted from the generator widget so the trim screen can offer the same
/// controls. Both screens are asking the ranker the same question — which of
/// these weeks is better — and a second, smaller set of knobs on one of them
/// would mean the answer depended on which screen you asked from.
class ConstraintsPanel extends StatefulWidget {
  const ConstraintsPanel({
    super.key,
    required this.controller,
    required this.availableCourses,
    this.showInstructors = true,
    this.title = 'Constraints & Preferences',
  });

  final TimetableGeneratorController controller;
  final List<Course> availableCourses;

  /// Instructor avoidance and ranking read the *mandatory* course list to know
  /// whose names to offer. Trimming has no mandatory list worth speaking of —
  /// only whatever the student pinned — so the group is left out there rather
  /// than shown permanently greyed.
  final bool showInstructors;

  final String title;

  @override
  State<ConstraintsPanel> createState() => _ConstraintsPanelState();
}

class _ConstraintsPanelState extends State<ConstraintsPanel> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),

        // Schedule group
        ConstraintGroup(
          icon: Icons.schedule,
          title: 'Schedule',
          children: [
            ConstraintRow(
              label: 'Max hours/day',
              child: AppDropdown<int>(
                width: 80,
                value: widget.controller.maxHoursPerDay,
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}'),
                )),
                onChanged: (value) {
                  if (value != null) widget.controller.maxHoursPerDay = value;
                },
              ),
            ),
            _buildCheckConstraint('Avoid back-to-back classes', widget.controller.avoidBackToBack, (v) => widget.controller.avoidBackToBack = v ?? false),
            _buildCheckConstraint('Minimize gaps between classes', widget.controller.minimizeGaps, (v) => widget.controller.minimizeGaps = v ?? false),
            // Clearing lunch protection also drops requireLunchFree; that
            // cascade lives in the controller's setter.
            _buildCheckConstraint('Protect lunch break (12–2 PM)', widget.controller.protectLunchBreak, (v) => widget.controller.protectLunchBreak = v ?? false),
            if (widget.controller.protectLunchBreak)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: RequireToggle(
                  value: widget.controller.requireLunchFree,
                  onChanged: (v) => widget.controller.requireLunchFree = v,
                ),
              ),
            ConstraintRow(
              label: 'Prefer classes in',
              child: AppDropdown<TimeOfDayPreference>(
                value: widget.controller.timeOfDayPreference,
                items: const [
                  DropdownMenuItem(value: TimeOfDayPreference.none, child: Text('No preference')),
                  DropdownMenuItem(value: TimeOfDayPreference.morning, child: Text('Morning (before 12 PM)')),
                  DropdownMenuItem(value: TimeOfDayPreference.afternoon, child: Text('Afternoon (after 12 PM)')),
                ],
                onChanged: (value) => widget.controller.timeOfDayPreference = value ?? TimeOfDayPreference.none,
              ),
            ),
            const SizedBox(height: 8),
            _buildClassHoursWindow(),
            const SizedBox(height: 12),
            _buildFreeDayRanking(),
            const SizedBox(height: 12),
            _buildTimeAvoidance(),
            const SizedBox(height: 12),
            _buildLabAvoidance(),
          ],
        ),
        const SizedBox(height: 10),

        if (widget.showInstructors) ...[
          ConstraintGroup(
            icon: Icons.person,
            title: 'Instructors',
            children: [
              _buildInstructorAvoidance(),
              const SizedBox(height: 12),
              _buildInstructorRanking(),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Exams group
        ConstraintGroup(
          icon: Icons.event,
          title: 'Exams',
          children: [
            ConstraintRow(
              label: 'Preferred midsem',
              child: AppDropdown<TimeSlot?>(
                value: widget.controller.preferredMidsemSlot,
                hint: const Text('Any', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                  ...TimeSlotInfo.getMidSemSlots().map((slot) => DropdownMenuItem(
                    value: slot,
                    child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.campusId)),
                  )),
                ],
                onChanged: (value) => widget.controller.preferredMidsemSlot = value,
              ),
            ),
            ConstraintRow(
              label: 'Preferred compre',
              child: AppDropdown<TimeSlot?>(
                value: widget.controller.preferredCompreSlot,
                hint: const Text('Any', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                  ...TimeSlotInfo.getEndSemSlots().map((slot) => DropdownMenuItem(
                    value: slot,
                    child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.campusId)),
                  )),
                ],
                onChanged: (value) => widget.controller.preferredCompreSlot = value,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Short clock label for an hour slot (1 = 8 AM … 12 = 7 PM).
  String _slotClockLabel(int slot) {
    final hour24 = slot + 7; // slot 1 → 08:00
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 > 12 ? hour24 - 12 : hour24;
    return '$hour12 $period';
  }

  /// Soft "no classes before X / after Y" window. A full 1–12 range means no
  /// bound (nulls on the controller); narrowing either end sets that bound.
  Widget _buildClassHoursWindow() {
    final start = (widget.controller.earliestStartSlot ?? 1).toDouble();
    final end = (widget.controller.latestEndSlot ?? 12).toDouble();
    final isBounded = widget.controller.earliestStartSlot != null || widget.controller.latestEndSlot != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Class hours window', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(
              isBounded
                  ? '${_slotClockLabel(start.round())} – ${_slotClockLabel(end.round())}'
                  : 'Any time',
              style: TextStyle(
                fontSize: 12,
                color: isBounded ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isBounded)
              InkResponse(
                onTap: widget.controller.clearHoursWindow,
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
          ],
        ),
        RangeSlider(
          min: 1,
          max: 12,
          divisions: 11,
          values: RangeValues(start, end),
          labels: RangeLabels(_slotClockLabel(start.round()), _slotClockLabel(end.round())),
          onChanged: (values) => widget.controller.setHoursWindow(
            startSlot: values.start.round(),
            endSlot: values.end.round(),
          ),
        ),
        Text(
          'Classes outside this window are penalised, not blocked.',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
        ),
        if (isBounded)
          RequireToggle(
            value: widget.controller.requireHoursWindow,
            onChanged: (v) => widget.controller.requireHoursWindow = v,
          ),
      ],
    );
  }

  Widget _buildCheckConstraint(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onChanged: onChanged,
    );
  }

  Widget _buildFreeDayRanking() {
    final unranked = DayOfWeek.values
        .where((d) => !widget.controller.freeDayPreference.contains(d))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Free day preference:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              if (widget.controller.freeDayPreference.isNotEmpty)
                TextButton(
                  onPressed: widget.controller.clearFreeDayPreference,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap days in order of preference (most wanted free day first)',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.controller.freeDayPreference.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: widget.controller.freeDayPreference.length,
              onReorderItem: widget.controller.reorderFreeDayPreference,
              itemBuilder: (context, index) {
                final day = widget.controller.freeDayPreference[index];
                return Container(
                  key: ValueKey(day),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        getDayName(day, abbreviated: true),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => widget.controller.removeFreeDayPreference(day),
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: 'Remove ${getDayName(day, abbreviated: true)}',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
          if (unranked.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unranked.map((day) {
                return ActionChip(
                  label: Text(getDayName(day, abbreviated: true), style: const TextStyle(fontSize: 12)),
                  onPressed: () => widget.controller.toggleFreeDayPreference(day),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          if (widget.controller.freeDayPreference.isNotEmpty)
            RequireToggle(
              value: widget.controller.requireFreeDays,
              onChanged: (v) => widget.controller.requireFreeDays = v,
            ),
        ],
      ),
    );
  }

  Widget _buildTimeAvoidance() {
    return ChipListSection(
      title: 'Avoid time slots:',
      actionLabel: 'Add',
      onAction: _addTimeAvoidance,
      chips: [
        for (final (index, a) in widget.controller.avoidTimes.indexed)
          RemovableChip(
            label: '${a.day.name}: ${_formatAvoidTimeHours(a.hours)}',
            onRemove: () => widget.controller.removeTimeAvoidance(index),
          ),
      ],
    );
  }

  Widget _buildLabAvoidance() {
    return ChipListSection(
      title: 'Avoid labs on:',
      actionLabel: 'Add',
      onAction: _addLabAvoidance,
      chips: [
        for (final (index, a) in widget.controller.avoidLabs.indexed)
          RemovableChip(
            label: '${a.day.name}: ${_formatAvoidTimeHours(a.hours)} (Labs)',
            onRemove: () => widget.controller.removeLabAvoidance(index),
            tint: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }

  Widget _buildInstructorAvoidance() {
    return ChipListSection(
      title: 'Avoid instructors:',
      actionLabel: 'Add',
      onAction: widget.controller.mandatoryCourses.isNotEmpty ? _addInstructorAvoidance : null,
      emptyHint: widget.controller.mandatoryCourses.isEmpty
          ? 'Select courses first to see available instructors'
          : null,
      chips: [
        for (final (index, name) in widget.controller.avoidedInstructors.indexed)
          RemovableChip(
            label: name,
            onRemove: () => widget.controller.removeAvoidedInstructor(index),
            tint: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }

  Widget _buildInstructorRanking() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Rank instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.controller.mandatoryCourses.isNotEmpty ? _showInstructorRankingDialog : null,
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Rank', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (widget.controller.instructorRankings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Current Rankings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.controller.instructorRankings.length} course${widget.controller.instructorRankings.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppTappable(
                      onTap: () => widget.controller.setInstructorRankings(const {}),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.clear_all,
                          size: 14,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.controller.instructorRankings.entries.map((entry) {
                        final courseCode = entry.key;
                        final rankings = entry.value;
                        final totalRanked = rankings.lectureInstructors.length +
                                          rankings.practicalInstructors.length +
                                          rankings.tutorialInstructors.length;

                        return AppTappable(
                          onTap: () => _showInstructorRankingDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      courseCode,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        totalRanked.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (rankings.lectureInstructors.isNotEmpty)
                                      _buildSectionTypeBadge(context, 'L', rankings.lectureInstructors.length),
                                    if (rankings.practicalInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'P', rankings.practicalInstructors.length),
                                    ],
                                    if (rankings.tutorialInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'T', rankings.tutorialInstructors.length),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getTopInstructorSummary(rankings),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (widget.controller.mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Text(
              'Select courses first to rank instructors',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTypeBadge(BuildContext context, String sectionType, int count) {
    final scheme = Theme.of(context).colorScheme;
    Color badgeColor;
    switch (sectionType) {
      case 'L':
        badgeColor = scheme.primary;
        break;
      case 'P':
        badgeColor = AppDesign.success(context);
        break;
      case 'T':
        badgeColor = AppDesign.warning(context);
        break;
      default:
        badgeColor = AppDesign.muted(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$sectionType:$count',
        style: TextStyle(
          fontSize: ResponsiveService.clampedFontSize(context, 9),
          fontWeight: FontWeight.bold,
          color: scheme.onPrimary,
        ),
      ),
    );
  }

  String _getTopInstructorSummary(InstructorRankings rankings) {
    final topInstructors = <String>[];

    if (rankings.lectureInstructors.isNotEmpty) {
      topInstructors.add('L: ${rankings.lectureInstructors.first}');
    }
    if (rankings.practicalInstructors.isNotEmpty) {
      topInstructors.add('P: ${rankings.practicalInstructors.first}');
    }
    if (rankings.tutorialInstructors.isNotEmpty) {
      topInstructors.add('T: ${rankings.tutorialInstructors.first}');
    }

    if (topInstructors.isEmpty) return 'No rankings set';
    return topInstructors.join(' • ');
  }

  String _formatAvoidTimeHours(List<int> hours) {
    if (hours.isEmpty) return '';

    // The picked slots can be disjoint (e.g. 2 and 8), so group them into
    // contiguous runs and format each run — a plain first→last range would
    // misrepresent {2, 8} as the whole 9 AM–3:50 PM block.
    final sorted = [...hours]..sort();
    final runs = <List<int>>[];
    for (final h in sorted) {
      if (runs.isNotEmpty && h == runs.last.last + 1) {
        runs.last.add(h);
      } else {
        runs.add([h]);
      }
    }
    return runs
        .map((run) => run.length == 1
            ? TimeSlotInfo.getHourSlotName(run.first)
            : TimeSlotInfo.getHourRangeName(run))
        .join(', ');
  }

  Future<void> _addTimeAvoidance() async {
    // Existing avoided hours per day → the dialog locks them, and we merge into
    // the same-day entry so there's one clean chip per day.
    final existing = <DayOfWeek, Set<int>>{};
    for (final a in widget.controller.avoidTimes) {
      existing.putIfAbsent(a.day, () => <int>{}).addAll(a.hours);
    }

    final result = await showDialog<TimeAvoidance>(
      context: context,
      builder: (context) => TimeAvoidanceDialog(disabledByDay: existing),
    );

    // Merging into the same-day entry lives in the controller.
    if (result != null && mounted) widget.controller.addTimeAvoidance(result);
  }

  Future<void> _addLabAvoidance() async {
    // Existing avoided lab hours per day → the dialog locks them, and we merge
    // into the same-day entry so there's one clean chip per day.
    final existing = <DayOfWeek, Set<int>>{};
    for (final a in widget.controller.avoidLabs) {
      existing.putIfAbsent(a.day, () => <int>{}).addAll(a.hours);
    }

    final result = await showDialog<LabAvoidance>(
      context: context,
      builder: (context) => LabAvoidanceDialog(disabledByDay: existing),
    );

    if (result != null && mounted) widget.controller.addLabAvoidance(result);
  }

  Future<void> _addInstructorAvoidance() async {
    // Get instructors organized by course and section type to avoid duplicates
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};
    final Set<String> seenInstructorsLower = <String>{};

    for (final courseCode in [...widget.controller.mandatoryCourses, ...widget.controller.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(
          courseCode: courseCode,
          courseTitle: 'Unknown',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 0,
          sections: [],
        ),
      );

      final sectionTypeInstructors = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      // Track seen instructors per section type to avoid duplicates within each section type
      final sectionTypeSeenLower = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      for (final section in course.sections) {
        if (section.instructor.isNotEmpty) {
          // Determine section type
          String sectionType = 'Lecture'; // default
          if (section.type.toString().contains('SectionType.L')) {
            sectionType = 'Lecture';
          } else if (section.type.toString().contains('SectionType.T')) {
            sectionType = 'Tutorial';
          } else if (section.type.toString().contains('SectionType.P')) {
            sectionType = 'Practical';
          }

          // Split comma-separated instructors into individual instructors
          final instructorList = section.instructor.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
          for (final instructor in instructorList) {
            final instructorLower = instructor.toLowerCase();

            // Only add if we haven't seen this instructor in this section type before
            if (!sectionTypeSeenLower[sectionType]!.contains(instructorLower)) {
              sectionTypeSeenLower[sectionType]!.add(instructorLower);
              sectionTypeInstructors[sectionType]!.add(instructor);

              // Also track globally to avoid duplicates across courses
              seenInstructorsLower.add(instructorLower);
            }
          }
        }
      }

      // Convert sets to sorted lists and filter out empty section types
      final filteredSectionInstructors = <String, List<String>>{};
      for (final entry in sectionTypeInstructors.entries) {
        if (entry.value.isNotEmpty) {
          filteredSectionInstructors[entry.key] = entry.value.toList()..sort();
        }
      }

      if (filteredSectionInstructors.isNotEmpty) {
        courseSectionInstructors[courseCode] = filteredSectionInstructors;
      }
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => InstructorAvoidanceDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentlyAvoided: widget.controller.avoidedInstructors,
      ),
    );

    if (result != null && mounted) {
      // Keys are "courseCode-sectionType-instructorName"; the name is rejoined
      // in case it contained hyphens of its own.
      widget.controller.addAvoidedInstructors(result
          .map((key) => key.split('-'))
          .where((parts) => parts.length >= 3)
          .map((parts) => parts.sublist(2).join('-')));
    }
  }

  Future<void> _showInstructorRankingDialog() async {
    // Get instructors organized by course and section type
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};

    for (final courseCode in [...widget.controller.mandatoryCourses, ...widget.controller.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );

      courseSectionInstructors[courseCode] = {
        'L': [],
        'P': [],
        'T': [],
      };

      for (final section in course.sections) {
        final sectionTypeStr = section.type.toString().split('.').last;
        if (courseSectionInstructors[courseCode]!.containsKey(sectionTypeStr)) {
          final instructor = section.instructor.trim();
          if (instructor.isNotEmpty &&
              !courseSectionInstructors[courseCode]![sectionTypeStr]!.contains(instructor)) {
            courseSectionInstructors[courseCode]![sectionTypeStr]!.add(instructor);
          }
        }
      }
    }

    final result = await showDialog<Map<String, InstructorRankings>>(
      context: context,
      builder: (context) => InstructorRankingDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentRankings: Map.from(widget.controller.instructorRankings),
      ),
    );

    if (result != null && mounted) widget.controller.setInstructorRankings(result);
  }

}
