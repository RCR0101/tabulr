import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable_reconciliation.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import 'common/app_dialog.dart';
import 'common/app_button.dart';

/// Surfaces what a course-data re-upload changed in the student's own timetable.
///
/// Shown once per change set (the reconcile persists its result, so a reopened
/// timetable no longer differs): a toast that names the scale of the change and
/// a "Show details" action that opens [_dialog] with the field-by-field diff.
class TimetableChangesNotice {
  const TimetableChangesNotice._();

  /// Pops a toast if [reconciliation] has anything to report. Safe to call with
  /// null or an empty report — it simply does nothing.
  static void notify(
    BuildContext context,
    TimetableReconciliation? reconciliation,
  ) {
    if (reconciliation == null || !reconciliation.hasChanges) return;

    final updated = reconciliation.updatedCount;
    final removed = reconciliation.removedCount;
    final String message;
    if (updated > 0 && removed > 0) {
      message = 'Course data was updated — ${_courses(updated)} changed and '
          '${_courses(removed)} no longer offered.';
    } else if (removed > 0) {
      message = '${_courses(removed)} in your timetable '
          '${removed == 1 ? 'is' : 'are'} no longer offered.';
    } else {
      message = 'Course data was updated — ${_courses(updated)} in your '
          'timetable changed.';
    }

    ToastService.showWarning(
      message,
      actionLabel: 'Show details',
      onAction: () => _show(context, reconciliation),
    );
  }

  static String _courses(int n) => n == 1 ? '1 course' : '$n courses';

  static void _show(
    BuildContext context,
    TimetableReconciliation reconciliation,
  ) {
    AppDialog.adaptive(
      context: context,
      title: 'What changed',
      content: SizedBox(
        width: 460,
        child: _ChangesList(reconciliation: reconciliation),
      ),
      actions: [
        AppButton(
          label: 'Got it',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ChangesList extends StatelessWidget {
  const _ChangesList({required this.reconciliation});

  final TimetableReconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
          child: Text(
            'The latest course data differs from what you had saved. Your '
            'selections were kept; updated details were applied automatically.',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final change in reconciliation.changes)
                  _ChangeCard(change: change),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final SectionChange change;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.spacingSm),
      padding: const EdgeInsets.all(AppDesign.spacingSm + 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: AppDesign.borderRadiusSm,
        border: Border.all(
          color: (change.isRemoved ? scheme.error : scheme.outline)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${change.courseCode} · ${change.sectionId}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (change.isRemoved)
                _pill('No longer offered', scheme.error, scheme),
            ],
          ),
          if (change.courseTitle.isNotEmpty &&
              change.courseTitle != change.courseCode) ...[
            const SizedBox(height: 2),
            Text(
              change.courseTitle,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (change.isRemoved)
            Text(
              'Kept in your timetable so nothing is lost — you may want to '
              'remove or replace it.',
              style: TextStyle(fontSize: 12, color: scheme.error),
            )
          else
            for (final field in change.changedFields)
              _fieldRow(context, field, change),
        ],
      ),
    );
  }

  Widget _fieldRow(BuildContext context, String field, SectionChange change) {
    final scheme = Theme.of(context).colorScheme;
    final (before, after) = _values(field, change);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              field,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  before.isEmpty ? '—' : before,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Icon(Icons.arrow_forward_rounded,
                    size: 13,
                    color: scheme.onSurface.withValues(alpha: 0.4)),
                Text(
                  after.isEmpty ? '—' : after,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _values(String field, SectionChange change) {
    final old = change.oldSection;
    final fresh = change.newSection;
    switch (field) {
      case 'Room':
        return (old.room, fresh?.room ?? '');
      case 'Instructor':
        return (old.instructor, fresh?.instructor ?? '');
      case 'Timing':
        return (
          TimeSlotInfo.getFormattedSchedule(old.schedule),
          fresh == null ? '' : TimeSlotInfo.getFormattedSchedule(fresh.schedule),
        );
      default:
        return ('', '');
    }
  }

  Widget _pill(String text, Color color, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
