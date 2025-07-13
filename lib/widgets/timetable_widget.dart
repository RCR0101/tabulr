import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

enum TimetableSize {
  compact,
  medium,
  large,
  extraLarge,
}

class TimetableWidget extends StatefulWidget {
  final List<TimetableSlot> timetableSlots;
  final List<String> incompleteSelectionWarnings;
  final VoidCallback? onClear;
  final Function(String courseCode, String sectionId)? onRemoveSection;
  final TimetableSize size;
  final Function(TimetableSize)? onSizeChanged;
  final bool isForExport;
  final GlobalKey? tableKey;
  final bool hasUnsavedChanges;
  final bool isSaving;
  final VoidCallback? onSave;

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
    this.hasUnsavedChanges = false,
    this.isSaving = false,
    this.onSave,
  });

  @override
  State<TimetableWidget> createState() => _TimetableWidgetState();
}

class _TimetableWidgetState extends State<TimetableWidget> {
  String? _hoveredCourse; // Track which course is being hovered

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
                onSelected: widget.onSizeChanged,
                enabled: widget.onSizeChanged != null,
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
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getSizeIcon(widget.size), size: 16),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 16),
              // Save button
              if (!widget.isForExport && widget.onSave != null)
                ElevatedButton.icon(
                  onPressed: widget.hasUnsavedChanges && !widget.isSaving ? widget.onSave : null,
                  icon: widget.isSaving 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        widget.hasUnsavedChanges ? Icons.save : Icons.check,
                        size: 16,
                      ),
                  label: Text(
                    widget.isSaving ? 'Saving...' : 
                    widget.hasUnsavedChanges ? 'Save' : 'Saved',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.hasUnsavedChanges 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.tertiary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (widget.timetableSlots.isNotEmpty && widget.onClear != null)
                ElevatedButton.icon(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.2),
                    foregroundColor: Theme.of(context).colorScheme.error,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        widget.isForExport
            ? Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1,
                  ),
                ),
                child: RepaintBoundary(
                  key: widget.tableKey,
                  child: IntrinsicWidth(
                    child: IntrinsicHeight(
                      child: DataTable(
                        columnSpacing: _getColumnSpacing(widget.size),
                        horizontalMargin: _getHorizontalMargin(widget.size),
                        dataRowHeight: _getDataRowHeight(widget.size),
                        headingRowHeight: 60,
                        dividerThickness: 0,
                        border: TableBorder.all(color: Colors.transparent),
                        columns: [
                        DataColumn(
                          label: SizedBox(
                            width: _getTimeColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                            width: _getDayColumnWidth(widget.size),
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
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.2),
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
                          key: widget.tableKey,
                          child: DataTable(
                            columnSpacing: _getColumnSpacing(widget.size),
                            horizontalMargin: _getHorizontalMargin(widget.size),
                            dataRowHeight: _getDataRowHeight(widget.size),
                            headingRowHeight: 60,
                            dividerThickness: 0,
                            border: TableBorder.all(color: Colors.transparent, width: 0),
                          columns: [
                            DataColumn(
                              label: SizedBox(
                                width: _getTimeColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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
                                width: _getDayColumnWidth(widget.size),
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

    for (var slot in widget.timetableSlots) {
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
              width: _getTimeColumnWidth(widget.size),
              height: _getCellHeight(widget.size),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hour $hour',
                    style:  TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TimeSlotInfo.getHourSlotName(hour),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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
                width: _getDayColumnWidth(widget.size),
                height: _getCellHeight(widget.size),
                margin: EdgeInsets.all(_getCellMargin(widget.size)),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
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
    final sameCourseSlots = widget.timetableSlots
        .where((s) => s.courseCode == slot.courseCode && s.sectionId == slot.sectionId)
        .toList();
    
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hoveredCourse = '${slot.courseCode}-${slot.sectionId}';
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredCourse = null;
        });
      },
      child: Tooltip(
        message: _buildTooltipContent(sameCourseSlots),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        textStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
        child: Container(
          width: _getDayColumnWidth(widget.size),
          height: _getCellHeight(widget.size),
          margin: EdgeInsets.all(_getCellMargin(widget.size)),
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
                padding: EdgeInsets.all(_getCellPadding(widget.size)),
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
                          fontSize: _getCourseCodeFontSize(widget.size),
                          color: Theme.of(context).colorScheme.onPrimary,
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (widget.size != TimetableSize.compact) ...[
                      Flexible(
                        flex: 2,
                        child: Text(
                          slot.courseTitle,
                          style: TextStyle(
                            fontSize: _getCourseTitleFontSize(widget.size),
                            color: const Color(0xFFE6EDF3),
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: _getCourseTitleMaxLines(widget.size),
                        ),
                      ),
                    ],
                    Flexible(
                      flex: 2,
                      child: Text(
                        slot.sectionId,
                        style: TextStyle(
                          fontSize: _getSectionIdFontSize(widget.size),
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
                          fontSize: _getRoomFontSize(widget.size),
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
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    textStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).shadowColor.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.warning,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                ),
              if (widget.onRemoveSection != null && _hoveredCourse == '${slot.courseCode}-${slot.sectionId}')
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => widget.onRemoveSection!(slot.courseCode, slot.sectionId),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).shadowColor.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child:  Icon(
                        Icons.close,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSecondary,
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
      const Color(0xFF58A6FF),
      const Color(0xFF56D364),
      const Color(0xFFFF922B),
      const Color(0xFFBD561D),
      const Color(0xFF39C5CF),
      const Color(0xFF6F42C1),
      const Color(0xFFDA3633),
      const Color(0xFFDB61A2),
      const Color(0xFF39C5CF),
      const Color(0xFFD4A72C),
    ];
    
    return colors[hash.abs() % colors.length];
  }

  bool _hasIncompleteSelection(String courseCode) {
    return widget.incompleteSelectionWarnings.any((warning) => warning.startsWith(courseCode));
  }

  String _getIncompleteSelectionWarning(String courseCode) {
    final warnings = widget.incompleteSelectionWarnings
        .where((warning) => warning.startsWith(courseCode))
        .toList();
    
    if (warnings.isEmpty) return '';
    return warnings.join('\n');
  }

  // Size-specific dimension helpers
  double _getDayColumnWidth(TimetableSize size) {
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

  double _getTimeColumnWidth(TimetableSize size) {
    return _getDayColumnWidth(size) * 0.75;
  }

  double _getCellHeight(TimetableSize size) {
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

  double _getCellMargin(TimetableSize size) {
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

  double _getColumnSpacing(TimetableSize size) {
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

  double _getHorizontalMargin(TimetableSize size) {
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

  double _getDataRowHeight(TimetableSize size) {
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

  IconData _getSizeIcon(TimetableSize size) {
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
  double _getCourseCodeFontSize(TimetableSize size) {
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

  double _getCourseTitleFontSize(TimetableSize size) {
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

  double _getSectionIdFontSize(TimetableSize size) {
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

  double _getRoomFontSize(TimetableSize size) {
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

  double _getCellPadding(TimetableSize size) {
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

  double _getTextSpacing(TimetableSize size) {
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

  int _getCourseTitleMaxLines(TimetableSize size) {
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