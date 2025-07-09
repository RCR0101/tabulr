import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

class TimetableWidget extends StatelessWidget {
  final List<TimetableSlot> timetableSlots;
  final List<String> incompleteSelectionWarnings;
  final VoidCallback? onClear;
  final Function(String courseCode, String sectionId)? onRemoveSection;

  const TimetableWidget({
    super.key,
    required this.timetableSlots,
    this.incompleteSelectionWarnings = const [],
    this.onClear,
    this.onRemoveSection,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 800,
        maxWidth: double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Weekly Timetable',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              if (timetableSlots.isNotEmpty && onClear != null)
                ElevatedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.2),
                    foregroundColor: Colors.red,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF30363D),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Scrollbar(
              scrollbarOrientation: ScrollbarOrientation.bottom,
              thickness: 8,
              radius: const Radius.circular(4),
              child: Scrollbar(
                scrollbarOrientation: ScrollbarOrientation.right,
                thickness: 8,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const ClampingScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 24,
                  dataRowHeight: 100,
                  headingRowHeight: 60,
                  columns: const [
                    DataColumn(
                      label: SizedBox(
                        width: 120,
                        child: Text(
                          'Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Monday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Tuesday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Wednesday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Thursday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Friday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          'Saturday',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: _buildRows(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),);
  }

  List<DataRow> _buildRows(BuildContext context) {
    List<DataRow> rows = [];
    Map<int, Map<DayOfWeek, TimetableSlot?>> timeTable = {};

    for (var slot in timetableSlots) {
      for (var hour in slot.hours) {
        timeTable[hour] ??= {};
        timeTable[hour]![slot.day] = slot;
      }
    }

    for (int hour = 1; hour <= 10; hour++) {
      rows.add(DataRow(
        cells: [
          DataCell(
            Container(
              width: 120,
              height: 80,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Center(
                child: Text(
                  TimeSlotInfo.getHourSlotName(hour),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFF0F6FC),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          ...DayOfWeek.values.map((day) {
            final slot = timeTable[hour]?[day];
            if (slot != null) {
              return DataCell(
                _buildTimetableCell(context, slot, hour, day),
              );
            }
            return DataCell(
              Container(
                width: 160,
                height: 80,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
              ),
            );
          }).toList(),
        ],
      ));
    }

    return rows;
  }

  Widget _buildTimetableCell(BuildContext context, TimetableSlot slot, int hour, DayOfWeek day) {
    // Find all slots for the same course to show in hover
    final sameCourseSlots = timetableSlots
        .where((s) => s.courseCode == slot.courseCode && s.sectionId == slot.sectionId)
        .toList();
    
    return MouseRegion(
      onEnter: (_) {},
      onExit: (_) {},
      child: Tooltip(
        message: _buildTooltipContent(sameCourseSlots),
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        textStyle: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 12),
        child: Container(
          width: 160,
          height: 80,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _getCourseColor(slot.courseCode).withOpacity(0.9),
                _getCourseColor(slot.courseCode).withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _getCourseColor(slot.courseCode).withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: _getCourseColor(slot.courseCode).withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        slot.courseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Color(0xFFFFFFFF),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Flexible(
                      child: Text(
                        slot.courseTitle,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFE6EDF3),
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Flexible(
                      child: Text(
                        slot.sectionId,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE6EDF3),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Flexible(
                      child: Text(
                        slot.room,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFE6EDF3),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Warning icon for incomplete course selections
              if (_hasIncompleteSelection(slot.courseCode))
                Positioned(
                  top: 2,
                  left: 2,
                  child: Tooltip(
                    message: _getIncompleteSelectionWarning(slot.courseCode),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    textStyle: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 12),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.warning,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (onRemoveSection != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemoveSection!(slot.courseCode, slot.sectionId),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      );
  }

  String _buildTooltipContent(List<TimetableSlot> slots) {
    if (slots.isEmpty) return '';
    
    final courseCode = slots.first.courseCode;
    final sectionId = slots.first.sectionId;
    final instructor = slots.first.instructor;
    
    final timeSlots = <String>[];
    for (var slot in slots) {
      for (var hour in slot.hours) {
        final timeSlot = '${_getDayAbbreviation(slot.day)} ${TimeSlotInfo.getHourSlotName(hour)}';
        if (!timeSlots.contains(timeSlot)) {
          timeSlots.add(timeSlot);
        }
      }
    }
    
    return '$courseCode ($sectionId)\\nInstructor: $instructor\\nSchedule:\\n${timeSlots.join('\\n')}';
  }

  String _getDayAbbreviation(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.M: return 'Mon';
      case DayOfWeek.T: return 'Tue';
      case DayOfWeek.W: return 'Wed';
      case DayOfWeek.Th: return 'Thu';
      case DayOfWeek.F: return 'Fri';
      case DayOfWeek.S: return 'Sat';
    }
  }

  Color _getCourseColor(String courseCode) {
    // Generate consistent colors based on course code
    final hash = courseCode.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.red,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
    ];
    
    return colors[hash.abs() % colors.length];
  }

  bool _hasIncompleteSelection(String courseCode) {
    return incompleteSelectionWarnings.any((warning) => warning.startsWith(courseCode));
  }

  String _getIncompleteSelectionWarning(String courseCode) {
    final warnings = incompleteSelectionWarnings
        .where((warning) => warning.startsWith(courseCode))
        .toList();
    
    if (warnings.isEmpty) return '';
    return warnings.join('\n');
  }
}