import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/data/campus_service.dart';
import '../utils/design_constants.dart';

enum SortColumn { course, midSem, endSem }

enum SortDirection { ascending, descending }

/// The exam schedule for the sections currently on a timetable.
///
/// Rewritten from a bordered `Table` whose header cells doubled as sort
/// controls — except below 768px, where they stopped being tappable and a
/// second row of sort buttons appeared *inside* the table instead. That is two
/// interaction models for one job, plus grid lines around every cell.
///
/// Every field the table carried is kept: course code, title, and the date and
/// time of both exams. Two things are added, because the data was already here
/// and only the presentation hid it — dates read as "10 Mar" rather than
/// "10/3", and two exams landing on one day are called out.
class ExamDatesWidget extends StatefulWidget {
  final List<SelectedSection> selectedSections;
  final List<Course> courses;

  const ExamDatesWidget({
    super.key,
    required this.selectedSections,
    required this.courses,
  });

  @override
  State<ExamDatesWidget> createState() => _ExamDatesWidgetState();
}

class _ExamDatesWidgetState extends State<ExamDatesWidget> {
  SortColumn _sortColumn = SortColumn.course;
  SortDirection _sortDirection = SortDirection.ascending;

  /// "10 Mar" reads unambiguously; "10/3" is a date-format coin toss.
  static String _formatDate(DateTime d) =>
      '${d.day} ${(d.month >= 1 && d.month <= 12) ? DayConstants.monthNames[d.month] : d.month}';

  /// Booklet slots arrive as "9:30AM-11:00AM"; give the meridiem its space.
  static String _formatSlot(String raw) => raw
      .replaceAllMapped(RegExp(r'(\d)(AM|PM)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('-', ' – ');

  @override
  Widget build(BuildContext context) {
    final examData = _getExamData();

    // Dates carrying more than one exam. Two papers in a day is the most useful
    // thing this screen can tell a student, and the table left them to spot it
    // by eye across three columns.
    final busyDays = <String, int>{};
    for (final e in examData) {
      for (final d in [e.midSemDate, e.endSemDate]) {
        if (d == null) continue;
        final key = '${d.year}-${d.month}-${d.day}';
        busyDays[key] = (busyDays[key] ?? 0) + 1;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, examData.length),
        if (examData.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 38, color: AppDesign.muted(context)),
                  const SizedBox(height: 12),
                  Text(
                    'No courses selected',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppDesign.muted(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add sections and their exams will appear here',
                    style:
                        TextStyle(fontSize: 12, color: AppDesign.muted(context)),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildColumnLabels(context),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: examData.length,
                    itemBuilder: (context, i) =>
                        _buildExamRow(context, examData[i], busyDays, i),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_note_outlined, size: 19, color: scheme.primary),
        const SizedBox(width: 8),
        const Text('Exam Schedule',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary)),
        ),
      ],
    );

    // The four sort controls plus the title do not fit a phone width. Rather
    // than shrink them below a comfortable tap target, they drop to their own
    // row — which costs one line and keeps every control full size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomForOneRow = constraints.maxWidth >= 560;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: roomForOneRow
              ? Row(children: [
                  title,
                  const Spacer(),
                  _buildSortControls(context),
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildSortControls(context),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// Two controls, not one: which field to sort on, and which way.
  ///
  /// They used to be the same gesture — tap a column to sort by it, tap it
  /// again to reverse — which meant reversing the order required knowing the
  /// field was already selected, and there was no way to see the direction
  /// without reading an arrow buried in a header.
  Widget _buildSortControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ascending = _sortDirection == SortDirection.ascending;

    Widget field(SortColumn column, String label) {
      final selected = _sortColumn == column;
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => setState(() => _sortColumn = column),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sort',
            style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.5))),
        field(SortColumn.course, 'Course'),
        field(SortColumn.midSem, 'Midsem'),
        field(SortColumn.endSem, 'Compre'),
        const SizedBox(width: 4),
        // Direction is its own button, so reversing never depends on which
        // field happens to be active.
        Tooltip(
          message: ascending ? 'Ascending' : 'Descending',
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => _sortDirection = ascending
                  ? SortDirection.descending
                  : SortDirection.ascending),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 15,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Column labels for the rows below. Aligned columns are the point: a student
  /// reading this is asking "when are my exams", which means scanning a date
  /// column top to bottom. The card layout this replaced put each course in its
  /// own box, which killed that and needed scrolling for four courses.
  Widget _buildColumnLabels(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle style() => TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: scheme.onSurface.withValues(alpha: 0.5),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('COURSE', style: style())),
          Expanded(flex: 3, child: Text('MIDSEM', style: style())),
          Expanded(flex: 3, child: Text('COMPRE', style: style())),
        ],
      ),
    );
  }

  Widget _buildExamRow(
      BuildContext context, ExamData exam, Map<String, int> busyDays, int index) {
    final scheme = Theme.of(context).colorScheme;

    bool sharesDay(DateTime? d) {
      if (d == null) return false;
      return (busyDays['${d.year}-${d.month}-${d.day}'] ?? 0) > 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        // A faint banded background instead of grid lines: it keeps the eye on
        // a row across three columns without drawing a box around every cell.
        color: index.isEven
            ? scheme.surfaceContainerLow.withValues(alpha: 0.5)
            : Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(exam.courseCode,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                if (exam.courseTitle.isNotEmpty &&
                    exam.courseTitle != exam.courseCode)
                  Text(
                    exam.courseTitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _examCell(context, exam.midSemDate, exam.midSemTime,
                scheme.tertiary, sharesDay(exam.midSemDate)),
          ),
          Expanded(
            flex: 3,
            child: _examCell(context, exam.endSemDate, exam.endSemTime,
                scheme.primary, sharesDay(exam.endSemDate)),
          ),
        ],
      ),
    );
  }

  Widget _examCell(BuildContext context, DateTime? date, String time,
      Color accent, bool sharesDay) {
    final scheme = Theme.of(context).colorScheme;

    if (date == null) {
      return Text('—',
          style: TextStyle(
              fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.35)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                _formatDate(date),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sharesDay) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Another exam falls on this day',
                child: Icon(Icons.warning_amber_rounded,
                    size: 13, color: AppDesign.warning(context)),
              ),
            ],
          ],
        ),
        if (time.isNotEmpty)
          Text(
            _formatSlot(time),
            style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurface.withValues(alpha: 0.6)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  List<ExamData> _getExamData() {
    final examDataList = <ExamData>[];
    final processedCourses = <String>{};

    for (var selectedSection in widget.selectedSections) {
      if (processedCourses.contains(selectedSection.courseCode)) continue;

      final course = widget.courses
          .where((c) => c.courseCode == selectedSection.courseCode)
          .firstOrNull;
      if (course == null) continue;

      processedCourses.add(selectedSection.courseCode);

      examDataList.add(ExamData(
        courseCode: course.courseCode,
        courseTitle: course.courseTitle,
        midSemDate: course.midSemExam?.date,
        midSemTime: course.midSemExam != null
            ? TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot,
                campus: CampusService.campusId)
            : '',
        endSemDate: course.endSemExam?.date,
        endSemTime: course.endSemExam != null
            ? TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot,
                campus: CampusService.campusId)
            : '',
      ));
    }

    _sortExamData(examDataList);
    return examDataList;
  }

  void _sortExamData(List<ExamData> examData) {
    examData.sort((a, b) {
      final int result = switch (_sortColumn) {
        SortColumn.course => a.courseCode.compareTo(b.courseCode),
        SortColumn.midSem => _compareDates(a.midSemDate, b.midSemDate),
        SortColumn.endSem => _compareDates(a.endSemDate, b.endSemDate),
      };
      return _sortDirection == SortDirection.ascending ? result : -result;
    });
  }

  /// Compares real dates rather than re-parsing "dd/mm" strings, which the old
  /// version did — and which silently fell back to a string comparison whenever
  /// the format did not match.
  ///
  /// A course with no exam sorts last in either direction: "unscheduled" is not
  /// a date and does not belong at the top of a chronological list.
  int _compareDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}

class ExamData {
  final String courseCode;
  final String courseTitle;
  final DateTime? midSemDate;
  final String midSemTime;
  final DateTime? endSemDate;
  final String endSemTime;

  ExamData({
    required this.courseCode,
    required this.courseTitle,
    required this.midSemDate,
    required this.midSemTime,
    required this.endSemDate,
    required this.endSemTime,
  });
}
