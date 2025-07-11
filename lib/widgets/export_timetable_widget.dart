import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'timetable_widget.dart';

class ExportTimetableWidget extends StatelessWidget {
  final List<TimetableSlot> timetableSlots;
  final TimetableSize size;

  const ExportTimetableWidget({
    super.key,
    required this.timetableSlots,
    this.size = TimetableSize.large,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Weekly Timetable',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF0F6FC),
              ),
            ),
          ),
          // Timetable grid
          _buildTimetableGrid(),
        ],
      ),
    );
  }

  Widget _buildTimetableGrid() {
    Map<int, Map<DayOfWeek, TimetableSlot?>> timeTable = {};
    
    // Populate timetable data
    for (var slot in timetableSlots) {
      for (var hour in slot.hours) {
        timeTable[hour] ??= {};
        timeTable[hour]![slot.day] = slot;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          _buildHeaderRow(),
          // Time slots
          ...List.generate(12, (index) {
            final hour = index + 1;
            return _buildTimeRow(hour, timeTable[hour] ?? {});
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Color(0xFF21262D),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Time', _getTimeColumnWidth()),
          _buildHeaderCell('Monday', _getDayColumnWidth()),
          _buildHeaderCell('Tuesday', _getDayColumnWidth()),
          _buildHeaderCell('Wednesday', _getDayColumnWidth()),
          _buildHeaderCell('Thursday', _getDayColumnWidth()),
          _buildHeaderCell('Friday', _getDayColumnWidth()),
          _buildHeaderCell('Saturday', _getDayColumnWidth()),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, double width) {
    return Container(
      width: width,
      height: 60,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFFF0F6FC),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRow(int hour, Map<DayOfWeek, TimetableSlot?> daySlots) {
    return Container(
      height: _getRowHeight(),
      child: Row(
        children: [
          // Time column
          _buildTimeCell(hour),
          // Day columns
          ...DayOfWeek.values.map((day) {
            final slot = daySlots[day];
            return _buildDayCell(slot);
          }),
        ],
      ),
    );
  }

  Widget _buildTimeCell(int hour) {
    return Container(
      width: _getTimeColumnWidth(),
      height: _getRowHeight(),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hour $hour',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF58A6FF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            TimeSlotInfo.getHourSlotName(hour),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Color(0xFFE6EDF3),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(TimetableSlot? slot) {
    if (slot == null) {
      return Container(
        width: _getDayColumnWidth(),
        height: _getRowHeight(),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          border: Border.all(color: const Color(0xFF30363D), width: 0.5),
        ),
      );
    }

    return Container(
      width: _getDayColumnWidth(),
      height: _getRowHeight(),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getCourseColor(slot.courseCode).withOpacity(0.9),
            _getCourseColor(slot.courseCode).withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.courseCode,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            slot.courseTitle,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFE6EDF3),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          Text(
            slot.sectionId,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE6EDF3),
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            slot.room,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFE6EDF3),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Color _getCourseColor(String courseCode) {
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

  double _getDayColumnWidth() {
    switch (size) {
      case TimetableSize.compact:
        return 140;
      case TimetableSize.medium:
        return 160;
      case TimetableSize.large:
        return 200;
      case TimetableSize.extraLarge:
        return 240;
    }
  }

  double _getTimeColumnWidth() {
    return _getDayColumnWidth() * 0.75;
  }

  double _getRowHeight() {
    switch (size) {
      case TimetableSize.compact:
        return 80;
      case TimetableSize.medium:
        return 90;
      case TimetableSize.large:
        return 110;
      case TimetableSize.extraLarge:
        return 130;
    }
  }
}

