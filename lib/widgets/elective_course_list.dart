import 'package:flutter/material.dart';
import '../models/academic_record.dart';
import '../models/course.dart';
import '../models/timetable_selection_link.dart';
import '../services/data/academic_record_service.dart';
import '../utils/design_constants.dart';
import 'course_list_widget.dart';

/// Results list shared by the Discipline and Humanities elective browsers.
///
/// Without a [selectionLink] this is a read-only catalog view. With one, the
/// Add/Remove buttons write through to the timetable the user opened the
/// browser from, and the list rebuilds on every change to that timetable — not
/// just the ones made here, since an exam-clash Override lands via a toast.
///
/// Owns the academic-record fetch so both elective screens get "already
/// cleared" markers without each wiring it up.
class ElectiveCourseList extends StatefulWidget {
  final List<Course> courses;

  /// Full campus catalog, so clash checks can see courses already on the
  /// timetable that aren't themselves electives.
  final List<Course> catalog;

  final TimetableSelectionLink? selectionLink;

  const ElectiveCourseList({
    super.key,
    required this.courses,
    required this.catalog,
    this.selectionLink,
  });

  @override
  State<ElectiveCourseList> createState() => _ElectiveCourseListState();
}

class _ElectiveCourseListState extends State<ElectiveCourseList> {
  AcademicRecord _record = AcademicRecord.empty;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final record = await AcademicRecordService().load();
    if (mounted) setState(() => _record = record);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.selectionLink;

    if (link == null) {
      return CourseListWidget(
        courses: widget.courses,
        catalog: widget.catalog,
        record: _record,
        selectedSections: const [],
        onSectionToggle: (_, __, ___) {},
      );
    }

    return ListenableBuilder(
      listenable: link.revision,
      builder: (context, _) => CourseListWidget(
        courses: widget.courses,
        catalog: widget.catalog,
        record: _record,
        selectedSections: link.selectedSections,
        onSectionToggle: link.onSectionToggle,
      ),
    );
  }
}

/// Strip above the results explaining that Add writes to the open timetable.
/// Renders nothing when the browser was opened without one.
class ElectiveTimetableBanner extends StatelessWidget {
  final TimetableSelectionLink? selectionLink;

  const ElectiveTimetableBanner({super.key, this.selectionLink});

  @override
  Widget build(BuildContext context) {
    final link = selectionLink;
    if (link == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingSm,
        vertical: AppDesign.spacingXs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline, size: 16, color: scheme.primary),
          const SizedBox(width: AppDesign.spacingXs),
          Expanded(
            child: Text(
              'Adding to "${link.timetableName}"',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
