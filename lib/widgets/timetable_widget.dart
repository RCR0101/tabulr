import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

class TimetableWidget extends StatelessWidget {
  final List<TimetableSlot> timetableSlots;
  final VoidCallback? onClear;
  final Function(String courseCode, String sectionId)? onRemoveSection;

  const TimetableWidget({
    super.key,
    required this.timetableSlots,
    this.onClear,
    this.onRemoveSection,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Weekly Timetable',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
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
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white,
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
      ],
    );
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
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  TimeSlotInfo.getHourSlotName(hour),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
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
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
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
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
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
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        slot.courseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        slot.sectionId,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        slot.room,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
}