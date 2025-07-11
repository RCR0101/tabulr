import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

enum TimetableSize {
  compact,
  medium,
  large,
  extraLarge,
}

class TimetableWidget extends StatelessWidget {
  final List<TimetableSlot> timetableSlots;
  final List<String> incompleteSelectionWarnings;
  final VoidCallback? onClear;
  final Function(String courseCode, String sectionId)? onRemoveSection;
  final TimetableSize size;
  final Function(TimetableSize)? onSizeChanged;
  final bool isForExport;
  final GlobalKey? tableKey;

  const TimetableWidget({
    super.key,
    required this.timetableSlots,
    this.incompleteSelectionWarnings = const [],
    this.onClear,
    this.onRemoveSection,
    this.size = TimetableSize.medium,
    this.onSizeChanged,
    this.isForExport = false,
    this.tableKey,
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
          padding: const EdgeInsets.all(8),
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
              PopupMenuButton<TimetableSize>(
                onSelected: onSizeChanged,
                enabled: onSizeChanged != null,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: TimetableSize.compact,
                      child: Row(
                        children: [
                          Icon(Icons.view_compact, size: 16),
                          SizedBox(width: 8),
                          Text('Compact'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: TimetableSize.medium,
                      child: Row(
                        children: [
                          Icon(Icons.view_module, size: 16),
                          SizedBox(width: 8),
                          Text('Medium'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: TimetableSize.large,
                      child: Row(
                        children: [
                          Icon(Icons.view_comfortable, size: 16),
                          SizedBox(width: 8),
                          Text('Large'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: TimetableSize.extraLarge,
                      child: Row(
                        children: [
                          Icon(Icons.view_agenda, size: 16),
                          SizedBox(width: 8),
                          Text('Extra Large'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getSizeIcon(), size: 16),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
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
        isForExport
            ? Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF30363D),
                    width: 1,
                  ),
                ),
                child: RepaintBoundary(
                  key: tableKey,
                  child: IntrinsicWidth(
                    child: IntrinsicHeight(
                      child: DataTable(
                        columnSpacing: _getColumnSpacing(),
                        horizontalMargin: _getHorizontalMargin(),
                        dataRowHeight: _getDataRowHeight(),
                        headingRowHeight: 60,
                        columns: [
                        DataColumn(
                          label: SizedBox(
                            width: _getTimeColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
                            width: _getDayColumnWidth(),
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
              )
            : Expanded(
                child: Container(
                  margin: const EdgeInsets.all(4),
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
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    physics: const ClampingScrollPhysics(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: RepaintBoundary(
                          key: tableKey,
                          child: DataTable(
                            columnSpacing: _getColumnSpacing(),
                            horizontalMargin: _getHorizontalMargin(),
                            dataRowHeight: _getDataRowHeight(),
                            headingRowHeight: 60,
                          columns: [
                            DataColumn(
                              label: SizedBox(
                                width: _getTimeColumnWidth(),
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
                                width: _getDayColumnWidth(),
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
                                width: _getDayColumnWidth(),
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
                                width: _getDayColumnWidth(),
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
                                width: _getDayColumnWidth(),
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
                                width: _getDayColumnWidth(),
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
                                width: _getDayColumnWidth(),
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

    for (int hour = 1; hour <= 12; hour++) {
      rows.add(DataRow(
        cells: [
          DataCell(
            Container(
              width: _getTimeColumnWidth(),
              height: _getCellHeight(),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
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
                width: _getDayColumnWidth(),
                height: _getCellHeight(),
                margin: EdgeInsets.all(_getCellMargin()),
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
          width: _getDayColumnWidth(),
          height: _getCellHeight(),
          margin: EdgeInsets.all(_getCellMargin()),
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
                padding: EdgeInsets.all(_getCellPadding()),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Flexible(
                      flex: 3,
                      child: Text(
                        slot.courseCode,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: _getCourseCodeFontSize(),
                          color: const Color(0xFFFFFFFF),
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (size != TimetableSize.compact) ...[
                      Flexible(
                        flex: 2,
                        child: Text(
                          slot.courseTitle,
                          style: TextStyle(
                            fontSize: _getCourseTitleFontSize(),
                            color: const Color(0xFFE6EDF3),
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: _getCourseTitleMaxLines(),
                        ),
                      ),
                    ],
                    Flexible(
                      flex: 2,
                      child: Text(
                        slot.sectionId,
                        style: TextStyle(
                          fontSize: _getSectionIdFontSize(),
                          color: const Color(0xFFE6EDF3),
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: Text(
                        slot.room,
                        style: TextStyle(
                          fontSize: _getRoomFontSize(),
                          color: const Color(0xFFE6EDF3),
                          height: 1.1,
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

  // Size-specific dimension helpers
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

  double _getCellHeight() {
    switch (size) {
      case TimetableSize.compact:
        return 70;
      case TimetableSize.medium:
        return 80;
      case TimetableSize.large:
        return 100;
      case TimetableSize.extraLarge:
        return 120;
    }
  }

  double _getCellMargin() {
    switch (size) {
      case TimetableSize.compact:
        return 1;
      case TimetableSize.medium:
        return 1;
      case TimetableSize.large:
        return 2;
      case TimetableSize.extraLarge:
        return 3;
    }
  }

  double _getColumnSpacing() {
    switch (size) {
      case TimetableSize.compact:
        return 12;
      case TimetableSize.medium:
        return 16;
      case TimetableSize.large:
        return 20;
      case TimetableSize.extraLarge:
        return 24;
    }
  }

  double _getHorizontalMargin() {
    switch (size) {
      case TimetableSize.compact:
        return 10;
      case TimetableSize.medium:
        return 12;
      case TimetableSize.large:
        return 16;
      case TimetableSize.extraLarge:
        return 20;
    }
  }

  double _getDataRowHeight() {
    switch (size) {
      case TimetableSize.compact:
        return 90;
      case TimetableSize.medium:
        return 100;
      case TimetableSize.large:
        return 120;
      case TimetableSize.extraLarge:
        return 140;
    }
  }

  IconData _getSizeIcon() {
    switch (size) {
      case TimetableSize.compact:
        return Icons.view_compact;
      case TimetableSize.medium:
        return Icons.view_module;
      case TimetableSize.large:
        return Icons.view_comfortable;
      case TimetableSize.extraLarge:
        return Icons.view_agenda;
    }
  }

  // Dynamic text sizing helpers
  double _getCourseCodeFontSize() {
    switch (size) {
      case TimetableSize.compact:
        return 12;
      case TimetableSize.medium:
        return 14;
      case TimetableSize.large:
        return 16;
      case TimetableSize.extraLarge:
        return 18;
    }
  }

  double _getCourseTitleFontSize() {
    switch (size) {
      case TimetableSize.compact:
        return 10;
      case TimetableSize.medium:
        return 11;
      case TimetableSize.large:
        return 12;
      case TimetableSize.extraLarge:
        return 14;
    }
  }

  double _getSectionIdFontSize() {
    switch (size) {
      case TimetableSize.compact:
        return 11;
      case TimetableSize.medium:
        return 12;
      case TimetableSize.large:
        return 13;
      case TimetableSize.extraLarge:
        return 15;
    }
  }

  double _getRoomFontSize() {
    switch (size) {
      case TimetableSize.compact:
        return 10;
      case TimetableSize.medium:
        return 11;
      case TimetableSize.large:
        return 12;
      case TimetableSize.extraLarge:
        return 13;
    }
  }

  double _getCellPadding() {
    switch (size) {
      case TimetableSize.compact:
        return 6;
      case TimetableSize.medium:
        return 8;
      case TimetableSize.large:
        return 10;
      case TimetableSize.extraLarge:
        return 12;
    }
  }

  double _getTextSpacing() {
    switch (size) {
      case TimetableSize.compact:
        return 1;
      case TimetableSize.medium:
        return 2;
      case TimetableSize.large:
        return 3;
      case TimetableSize.extraLarge:
        return 4;
    }
  }

  int _getCourseTitleMaxLines() {
    switch (size) {
      case TimetableSize.compact:
        return 0; // Hidden in compact mode
      case TimetableSize.medium:
        return 1;
      case TimetableSize.large:
        return 2;
      case TimetableSize.extraLarge:
        return 2;
    }
  }
}