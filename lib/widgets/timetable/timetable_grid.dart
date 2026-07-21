import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../models/timetable_display.dart';
import '../../utils/datetime_utils.dart';
import 'course_palette.dart';
import 'timetable_blocks.dart';

/// Which cell fields a block should render. Replaces the old stringly-typed
/// `_shouldShowField('courseCode')`, which silently returned true for typos.
enum TimetableField { courseCode, courseTitle, sectionId, instructor, room }

/// The week grid.
///
/// Two invariants drive the whole layout:
///
///  * **Columns divide the available width.** The old grid gave columns a fixed
///    width from the size enum — 1,267 px at medium — and leaned on
///    `InteractiveViewer` to cope, so on a 1440×900 laptop roughly a third of
///    the grid was on screen at first paint with no auto-fit. Here the column
///    width is measured, and only a viewport too narrow for a legible minimum
///    falls back to horizontal scrolling.
///  * **Row height is the only thing density controls**, and
///    [TimetableSize.fit] derives it from the viewport so the entire grid is
///    visible at once.
///
/// Headers are pinned on both axes, which the previous
/// `InteractiveViewer(constrained: false)` could not do: panning right lost the
/// time column and panning down lost the day names.
class TimetableGrid extends StatefulWidget {
  const TimetableGrid({
    super.key,
    required this.slots,
    required this.layout,
    required this.size,
    required this.palette,
    this.showAllHours = false,
    this.isForExport = false,
    this.visibleFields = const {
      TimetableField.courseCode,
      TimetableField.courseTitle,
      TimetableField.sectionId,
      TimetableField.instructor,
      TimetableField.room,
    },
    this.incompleteSelectionWarnings = const [],
    this.onSlotTap,
    this.onRemoveSection,
  });

  final List<TimetableSlot> slots;
  final TimetableLayout layout;
  final TimetableSize size;
  final CoursePalette palette;
  final bool showAllHours;
  final bool isForExport;
  final Set<TimetableField> visibleFields;
  final List<String> incompleteSelectionWarnings;
  final void Function(CourseBlock block)? onSlotTap;
  final void Function(String courseCode, String sectionId)? onRemoveSection;

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  final ValueNotifier<_GridFocus> _focus = ValueNotifier(const _GridFocus());
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _headerHorizontal = ScrollController();
  Timer? _nowTicker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _bodyHorizontal.addListener(_syncHeaderScroll);
    if (!widget.isForExport) {
      // The current-time line would otherwise drift until an unrelated rebuild
      // happened to refresh it.
      _nowTicker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _nowTicker?.cancel();
    _bodyHorizontal.removeListener(_syncHeaderScroll);
    _bodyHorizontal.dispose();
    _headerHorizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The header scrolls under `NeverScrollableScrollPhysics`; the body drives it
  /// so the two axes stay locked without a linked-controller package.
  void _syncHeaderScroll() {
    if (!_headerHorizontal.hasClients || !_bodyHorizontal.hasClients) return;
    if (_headerHorizontal.offset != _bodyHorizontal.offset) {
      _headerHorizontal.jumpTo(_bodyHorizontal.offset);
    }
  }

  /// Selecting a section highlights every block belonging to it, and survives
  /// the detail dialog closing so the answer to "where else does this meet?"
  /// stays on screen.
  void _selectSection(String? sectionKey) {
    _focus.value = _focus.value.copyWith(selectedKey: sectionKey, clearSelected: sectionKey == null);
  }

  TextScaler get _textScaler =>
      widget.isForExport ? TextScaler.noScaling : MediaQuery.textScalerOf(context);

  bool get _isTouch =>
      !widget.isForExport && MediaQuery.maybeOf(context) != null &&
      MediaQuery.sizeOf(context).width <= ResponsiveConstants.tabletBreakpoint;

  @override
  Widget build(BuildContext context) {
    final blocks = TimetableBlockMap.fromSlots(widget.slots);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _measure(constraints, blocks);
        final body = _buildBody(context, blocks, geometry);

        return GestureDetector(
          // Tapping the background clears the highlight. Blocks are descendants,
          // so their own detectors win the gesture arena first.
          behavior: HitTestBehavior.translucent,
          onTap: () => _selectSection(null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(context, geometry),
              if (widget.isForExport) body else Expanded(child: body),
            ],
          ),
        );
      },
    );
  }

  // ── Geometry ──────────────────────────────────────────────────────────────

  _GridGeometry _measure(BoxConstraints constraints, TimetableBlockMap blocks) {
    final vertical = widget.layout == TimetableLayout.vertical;
    final hours = blocks.visibleHours(showAll: widget.showAllHours);
    final days = blocks.visibleDays(showAll: widget.showAllHours);

    // Accessibility text scaling has to widen the gutter and heighten the rows,
    // or large type clips — the old grid hardcoded `headingRowHeight: 60` while
    // scaling the fonts inside it.
    final scale = _textScaler.scale(1.0).clamp(1.0, 1.6);

    final columnCount = vertical ? days.length : hours.length;
    final rowCount = vertical ? hours.length : days.length;

    final leadWidth = (vertical ? 62.0 : 78.0) * scale;
    final headerHeight = (vertical ? 42.0 : 50.0) * scale;

    final maxRow = vertical ? 132.0 : 168.0;
    double row;
    if (widget.size == TimetableSize.fit &&
        !widget.isForExport &&
        constraints.maxHeight.isFinite &&
        rowCount > 0) {
      row = (constraints.maxHeight - headerHeight) / rowCount;
    } else {
      row = (widget.size.fixedRowHeight ?? 84.0) * scale;
      if (!vertical) row *= 1.2; // A day row holds a whole day's worth of blocks.
    }
    row = row.clamp(34.0, maxRow);

    // Export sizes to content instead of dividing a viewport. Filling a fixed
    // capture width would hand a three-day timetable three 600 px columns; a
    // column proportional to the row keeps cards the same shape whatever the
    // week looks like, and the PNG comes out as wide as it needs to be.
    if (widget.isForExport) {
      return _GridGeometry(
        vertical: vertical,
        hours: hours,
        days: days,
        leadWidth: leadWidth,
        headerHeight: headerHeight,
        columnExtent: (row * 2.0).clamp(150.0, 300.0),
        rowExtent: row,
        needsHorizontalScroll: false,
      );
    }

    final available = (constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0) - leadWidth;
    final minColumn = vertical ? (_isTouch ? 84.0 : 96.0) : 62.0 * scale;

    var column = columnCount == 0 ? minColumn : available / columnCount;
    var needsHorizontalScroll = false;
    if (column < minColumn) {
      column = minColumn;
      needsHorizontalScroll = true;
    }

    return _GridGeometry(
      vertical: vertical,
      hours: hours,
      days: days,
      leadWidth: leadWidth,
      headerHeight: headerHeight,
      columnExtent: column,
      rowExtent: row,
      needsHorizontalScroll: needsHorizontalScroll,
    );
  }

  // ── Chrome ────────────────────────────────────────────────────────────────

  Widget _buildHeaderRow(BuildContext context, _GridGeometry geo) {
    final scheme = Theme.of(context).colorScheme;
    final labels = geo.vertical
        ? [for (final day in geo.days) _dayHeader(context, day, geo)]
        : [for (final hour in geo.hours) _hourHeader(context, hour, geo)];

    final cells = Row(
      children: [
        for (final label in labels) SizedBox(width: geo.columnExtent, child: label),
      ],
    );

    return Container(
      height: geo.headerHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        mainAxisSize: widget.isForExport ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SizedBox(width: geo.leadWidth),
          if (geo.needsHorizontalScroll)
            Expanded(
              child: SingleChildScrollView(
                controller: _headerHorizontal,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: cells,
              ),
            )
          else
            cells,
        ],
      ),
    );
  }

  Widget _dayHeader(BuildContext context, DayOfWeek day, _GridGeometry geo) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = !widget.isForExport && day == _todayOfWeek(_now);
    // Full day names need roughly 80 px; below that they truncate to noise.
    final abbreviated = geo.columnExtent < 104;
    return Center(
      child: Text(
        getDayName(day, abbreviated: abbreviated),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: _textScaler.scale(geo.columnExtent < 92 ? 12.0 : 13.5),
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
          color: isToday ? scheme.primary : scheme.onSurface.withValues(alpha: 0.75),
          letterSpacing: 0.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _hourHeader(BuildContext context, int hour, _GridGeometry geo) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            ScheduleConstants.hourLabels[hour] ?? '',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: _textScaler.scale(12.0),
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'H$hour',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: _textScaler.scale(9.5),
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildLeadColumn(BuildContext context, _GridGeometry geo) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: geo.leadWidth,
      child: Column(
        children: [
          for (final index in List.generate(geo.rowCount, (i) => i))
            SizedBox(
              height: geo.rowExtent,
              child: Center(
                child: geo.vertical
                    ? _hourLabel(context, geo.hours[index], geo, scheme)
                    : Text(
                        getDayName(geo.days[index], abbreviated: true),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: _textScaler.scale(12.5),
                          fontWeight: FontWeight.w600,
                          color: geo.days[index] == _todayOfWeek(_now) && !widget.isForExport
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hourLabel(
    BuildContext context,
    int hour,
    _GridGeometry geo,
    ColorScheme scheme,
  ) {
    final showHourNumber = geo.rowExtent >= 52;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          ScheduleConstants.hourLabels[hour] ?? '',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: _textScaler.scale(11.5),
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
          maxLines: 1,
        ),
        if (showHourNumber)
          Text(
            'H$hour',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: _textScaler.scale(9.5),
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
            maxLines: 1,
          ),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
  ) {
    final grid = _buildGridSurface(context, blocks, geo);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.isForExport ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _buildLeadColumn(context, geo),
        if (geo.needsHorizontalScroll)
          Expanded(
            child: SingleChildScrollView(
              controller: _bodyHorizontal,
              scrollDirection: Axis.horizontal,
              child: grid,
            ),
          )
        else
          grid,
      ],
    );

    // Export renders into an unbounded-height overlay, so it must size to
    // content and must not contain a scroll view.
    if (widget.isForExport) return row;

    return SingleChildScrollView(child: row);
  }

  Widget _buildGridSurface(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final todayIndex = _todayColumnIndex(geo);
    final nowOffset = _nowOffset(geo);

    return SizedBox(
      width: geo.bodyWidth,
      height: geo.bodyHeight,
      child: Stack(
        children: [
          if (todayIndex != null)
            Positioned(
              left: geo.vertical ? todayIndex * geo.columnExtent : 0,
              top: geo.vertical ? 0 : todayIndex * geo.rowExtent,
              width: geo.vertical ? geo.columnExtent : geo.bodyWidth,
              height: geo.vertical ? geo.bodyHeight : geo.rowExtent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.045),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GridLinesPainter(
                columnExtent: geo.columnExtent,
                rowExtent: geo.rowExtent,
                columnCount: geo.columnCount,
                rowCount: geo.rowCount,
                color: scheme.outline.withValues(alpha: 0.14),
              ),
            ),
          ),
          if (geo.vertical)
            Row(
              children: [
                for (final day in geo.days)
                  SizedBox(
                    width: geo.columnExtent,
                    child: _dayColumn(context, blocks, geo, day),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final day in geo.days)
                  SizedBox(
                    height: geo.rowExtent,
                    child: _dayRow(context, blocks, geo, day),
                  ),
              ],
            ),
          if (nowOffset != null)
            Positioned(
              top: geo.vertical ? nowOffset : 0,
              left: geo.vertical ? 0 : nowOffset,
              width: geo.vertical ? geo.bodyWidth : 1.5,
              height: geo.vertical ? 1.5 : geo.bodyHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Vertical layout: one column per day, walking the visible hours and
  /// emitting a single sized child per block.
  Widget _dayColumn(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
    DayOfWeek day,
  ) {
    final children = <Widget>[];
    int index = 0;
    while (index < geo.hours.length) {
      final hour = geo.hours[index];
      final block = blocks.blockStartingAt(day, hour);
      if (block == null) {
        children.add(SizedBox(height: geo.rowExtent));
        index++;
        continue;
      }
      // Clamp against the visible tail so a cropped grid cannot overflow.
      final span = (block.endHour.clamp(hour, geo.hours.last) - hour + 1)
          .clamp(1, geo.hours.length - index);
      children.add(
        SizedBox(
          height: geo.rowExtent * span,
          child: _buildBlock(context, block, geo.columnExtent, geo.rowExtent * span),
        ),
      );
      index += span;
    }
    return Column(children: children);
  }

  /// Horizontal layout: one row per day, walking the visible hours. Mirrors
  /// [_dayColumn] with the axes swapped, so a multi-hour block is one wide card
  /// rather than several adjacent ones.
  Widget _dayRow(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
    DayOfWeek day,
  ) {
    final children = <Widget>[];
    int index = 0;
    while (index < geo.hours.length) {
      final hour = geo.hours[index];
      final block = blocks.blockStartingAt(day, hour);
      if (block == null) {
        children.add(SizedBox(width: geo.columnExtent));
        index++;
        continue;
      }
      final span = (block.endHour.clamp(hour, geo.hours.last) - hour + 1)
          .clamp(1, geo.hours.length - index);
      children.add(
        SizedBox(
          width: geo.columnExtent * span,
          child: _buildBlock(
            context,
            block,
            geo.columnExtent * span,
            geo.rowExtent,
          ),
        ),
      );
      index += span;
    }
    return Row(children: children);
  }

  // ── Block card ────────────────────────────────────────────────────────────

  Widget _buildBlock(
    BuildContext context,
    CourseBlock block,
    double width,
    double height,
  ) {
    final accent = widget.palette.colorFor(block.slot.courseCode);
    final warning = _incompleteWarningFor(block.slot.courseCode);

    return ValueListenableBuilder<_GridFocus>(
      valueListenable: _focus,
      builder: (context, focus, _) {
        final isHovered = focus.hoveredKey == block.sectionKey;
        final isSelected = focus.selectedKey == block.sectionKey;
        return _BlockCard(
          key: ValueKey('block-${block.sectionKey}-${block.startHour}'),
          block: block,
          accent: accent,
          width: width,
          height: height,
          isHovered: isHovered,
          isSelected: isSelected,
          isTouch: _isTouch,
          isForExport: widget.isForExport,
          textScaler: _textScaler,
          visibleFields: widget.visibleFields,
          incompleteWarning: warning,
          onEnter: () => _focus.value = _focus.value.copyWith(hoveredKey: block.sectionKey),
          onExit: () {
            if (_focus.value.hoveredKey == block.sectionKey) {
              _focus.value = _focus.value.copyWith(clearHovered: true);
            }
          },
          onTap: () {
            _selectSection(block.sectionKey);
            widget.onSlotTap?.call(block);
          },
          onRemove: widget.onRemoveSection == null
              ? null
              : () => widget.onRemoveSection!(block.slot.courseCode, block.slot.sectionId),
        );
      },
    );
  }

  String? _incompleteWarningFor(String courseCode) {
    final matches = widget.incompleteSelectionWarnings
        .where((warning) => warning.startsWith(courseCode))
        .toList();
    return matches.isEmpty ? null : matches.join('\n');
  }

  // ── Today / now ───────────────────────────────────────────────────────────

  static DayOfWeek? _todayOfWeek(DateTime now) => switch (now.weekday) {
    DateTime.monday => DayOfWeek.M,
    DateTime.tuesday => DayOfWeek.T,
    DateTime.wednesday => DayOfWeek.W,
    DateTime.thursday => DayOfWeek.Th,
    DateTime.friday => DayOfWeek.F,
    DateTime.saturday => DayOfWeek.S,
    _ => null,
  };

  int? _todayColumnIndex(_GridGeometry geo) {
    if (widget.isForExport) return null;
    final today = _todayOfWeek(_now);
    if (today == null) return null;
    final index = geo.days.indexOf(today);
    return index < 0 ? null : index;
  }

  /// Distance along the hour axis for the current time, or null when outside
  /// teaching hours. Hour 1 starts at 08:00.
  double? _nowOffset(_GridGeometry geo) {
    if (widget.isForExport) return null;
    if (_todayOfWeek(_now) == null) return null;
    if (!geo.days.contains(_todayOfWeek(_now))) return null;

    final minutesSinceFirstHour = (_now.hour * 60 + _now.minute) - 8 * 60;
    if (minutesSinceFirstHour < 0) return null;

    final hoursElapsed = minutesSinceFirstHour / 60.0;
    if (hoursElapsed > geo.hours.length) return null;

    final extent = geo.vertical ? geo.rowExtent : geo.columnExtent;
    return hoursElapsed * extent;
  }
}

// ── Supporting types ────────────────────────────────────────────────────────

class _GridFocus {
  const _GridFocus({this.hoveredKey, this.selectedKey});

  final String? hoveredKey;
  final String? selectedKey;

  _GridFocus copyWith({
    String? hoveredKey,
    String? selectedKey,
    bool clearHovered = false,
    bool clearSelected = false,
  }) {
    return _GridFocus(
      hoveredKey: clearHovered ? null : (hoveredKey ?? this.hoveredKey),
      selectedKey: clearSelected ? null : (selectedKey ?? this.selectedKey),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GridFocus &&
      other.hoveredKey == hoveredKey &&
      other.selectedKey == selectedKey;

  @override
  int get hashCode => Object.hash(hoveredKey, selectedKey);
}

class _GridGeometry {
  const _GridGeometry({
    required this.vertical,
    required this.hours,
    required this.days,
    required this.leadWidth,
    required this.headerHeight,
    required this.columnExtent,
    required this.rowExtent,
    required this.needsHorizontalScroll,
  });

  final bool vertical;
  final List<int> hours;
  final List<DayOfWeek> days;
  final double leadWidth;
  final double headerHeight;
  final double columnExtent;
  final double rowExtent;
  final bool needsHorizontalScroll;

  int get columnCount => vertical ? days.length : hours.length;
  int get rowCount => vertical ? hours.length : days.length;
  double get bodyWidth => columnExtent * columnCount;
  double get bodyHeight => rowExtent * rowCount;
}

/// Hairlines only. The old grid drew a full 1 px outlined box around every empty
/// cell, which is most of a timetable — letting empty space read as empty is
/// most of what makes a calendar look calm.
class _GridLinesPainter extends CustomPainter {
  const _GridLinesPainter({
    required this.columnExtent,
    required this.rowExtent,
    required this.columnCount,
    required this.rowCount,
    required this.color,
  });

  final double columnExtent;
  final double rowExtent;
  final int columnCount;
  final int rowCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..isAntiAlias = false;

    for (int row = 1; row < rowCount; row++) {
      final y = row * rowExtent;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (int column = 1; column < columnCount; column++) {
      final x = column * columnExtent;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter old) =>
      old.columnExtent != columnExtent ||
      old.rowExtent != rowExtent ||
      old.columnCount != columnCount ||
      old.rowCount != rowCount ||
      old.color != color;
}

/// One class block. Content is chosen from the space actually available rather
/// than from the density enum, which is what collapses nine `switch (size)`
/// font/padding/radius/max-lines helpers into a single breakpoint table.
class _BlockCard extends StatelessWidget {
  const _BlockCard({
    super.key,
    required this.block,
    required this.accent,
    required this.width,
    required this.height,
    required this.isHovered,
    required this.isSelected,
    required this.isTouch,
    required this.isForExport,
    required this.textScaler,
    required this.visibleFields,
    required this.incompleteWarning,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    required this.onRemove,
  });

  final CourseBlock block;
  final Color accent;
  final double width;
  final double height;
  final bool isHovered;
  final bool isSelected;
  final bool isTouch;
  final bool isForExport;
  final TextScaler textScaler;
  final Set<TimetableField> visibleFields;
  final String? incompleteWarning;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  bool _shows(TimetableField field) => visibleFields.contains(field);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slot = block.slot;

    final inset = height < 44 ? 1.5 : 2.5;
    final metrics = _CardMetrics.forHeight(height, textScaler);

    final emphasis = isSelected ? 0.10 : (isHovered ? 0.06 : 0.0);
    final fill = accent.withValues(alpha: (isDark ? 0.16 : 0.10) + emphasis);

    // The remove affordance was hover-only, so it never appeared on touch —
    // `MouseRegion.onEnter` does not fire for a finger. Selection covers it.
    final showsRemove = onRemove != null && !isForExport && (isHovered || isSelected);

    final card = Container(
      margin: EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(height < 44 ? 6 : 9),
        border: Border.all(
          color: accent.withValues(alpha: isSelected ? 0.6 : (isHovered ? 0.42 : 0.24)),
          width: isSelected ? 1.4 : 1.0,
        ),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One accent rule per *block*, not per hour — the visible payoff
              // of merging contiguous hours.
              Container(width: 3, color: accent),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.padding,
                    vertical: metrics.padding * 0.7,
                  ),
                  // Measured rather than derived: computing the content box by
                  // subtracting insets and padding from the card height missed
                  // the 1 px border on each edge, and the card overflowed by
                  // exactly that much.
                  child: LayoutBuilder(
                    builder: (context, constraints) => _content(
                      context,
                      scheme,
                      metrics,
                      _ContentPlan.fit(
                        metrics,
                        constraints.maxHeight,
                        constraints.maxWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (incompleteWarning != null)
            Positioned(
              top: 1,
              right: showsRemove ? 22 : 1,
              child: Tooltip(
                message: incompleteWarning!,
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: scheme.secondary,
                ),
              ),
            ),
          if (showsRemove)
            Positioned(
              top: 1,
              right: 1,
              child: Semantics(
                label: 'Remove ${slot.courseCode} ${slot.sectionId}',
                button: true,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 11, color: scheme.onError),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (isForExport) return card;

    return Semantics(
      label:
          '${slot.courseCode} ${slot.sectionId}, ${block.timeRangeLabel}, ${slot.instructor}, ${slot.room}',
      button: true,
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: card),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ColorScheme scheme,
    _CardMetrics metrics,
    _ContentPlan plan,
  ) {
    final slot = block.slot;
    final lines = <Widget>[];

    if (_shows(TimetableField.courseCode)) {
      lines.add(
        Text(
          slot.courseCode,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: metrics.codeSize,
            fontWeight: FontWeight.w700,
            color: accent,
            height: 1.12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (plan.showsTitle && _shows(TimetableField.courseTitle) && slot.courseTitle.isNotEmpty) {
      lines.add(
        Text(
          slot.courseTitle,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: metrics.metaSize,
            color: scheme.onSurface.withValues(alpha: 0.9),
            height: 1.18,
          ),
          maxLines: plan.titleMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final trailing = <String>[
      if (plan.showsMeta && _shows(TimetableField.sectionId)) slot.sectionId,
      if (plan.showsMeta && _shows(TimetableField.room) && slot.room.isNotEmpty)
        slot.room,
    ];
    if (trailing.isNotEmpty) {
      lines.add(
        Text(
          trailing.join('  ·  '),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: metrics.metaSize,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface.withValues(alpha: 0.72),
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (plan.showsInstructor &&
        _shows(TimetableField.instructor) &&
        slot.instructor.isNotEmpty) {
      lines.add(
        Text(
          slot.instructor,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: metrics.metaSize,
            color: scheme.onSurface.withValues(alpha: 0.6),
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < lines.length; i++) ...[
          if (i > 0) SizedBox(height: metrics.gap),
          lines[i],
        ],
      ],
    );
  }
}

/// Type and spacing for a card, chosen from its overall height in three coarse
/// steps. Separate from [_ContentPlan] because the padding has to be decided
/// before the content box can be measured.
class _CardMetrics {
  const _CardMetrics({
    required this.codeSize,
    required this.metaSize,
    required this.padding,
    required this.gap,
  });

  final double codeSize;
  final double metaSize;
  final double padding;
  final double gap;

  // Matches the TextStyles in _BlockCard.
  static const double codeLineHeight = 1.12;
  static const double metaLineHeight = 1.18;

  double get codeLine => codeSize * codeLineHeight;
  double get metaLine => metaSize * metaLineHeight;

  factory _CardMetrics.forHeight(double height, TextScaler scaler) {
    if (height < 40) {
      return _CardMetrics(
        codeSize: scaler.scale(10.5),
        metaSize: scaler.scale(9.0),
        padding: 3,
        gap: 1,
      );
    }
    if (height < 96) {
      return _CardMetrics(
        codeSize: scaler.scale(12.5),
        metaSize: scaler.scale(10.0),
        padding: 5,
        gap: 2,
      );
    }
    return _CardMetrics(
      codeSize: scaler.scale(13.5),
      metaSize: scaler.scale(11.0),
      padding: 8,
      gap: 3,
    );
  }
}

/// Which lines a card can afford, given the content box it was actually handed.
///
/// Lines are admitted in order of usefulness at a glance — the code, then where
/// and which section, then what the course is, then who teaches it — and each
/// is kept only if its line height still leaves room. That is why a one-hour
/// card at medium density carries the instructor: four lines need about 70 px
/// of content box and a medium row leaves roughly 72. The previous
/// hand-tabulated thresholds put the instructor at 100 px and dropped it for no
/// reason.
class _ContentPlan {
  const _ContentPlan({
    required this.showsTitle,
    required this.titleMaxLines,
    required this.showsMeta,
    required this.showsInstructor,
  });

  final bool showsTitle;
  final int titleMaxLines;

  /// Section and room, joined onto one line.
  final bool showsMeta;

  final bool showsInstructor;

  static _ContentPlan fit(_CardMetrics metrics, double height, double width) {
    // Under these a title or an instructor name is a row of ellipses, so the
    // space is better spent on fewer, readable lines.
    final narrow = width < 78;
    final veryNarrow = width < 48;

    var remaining = height - metrics.codeLine;

    bool take(double lineHeight) {
      if (remaining - metrics.gap - lineHeight < 0) return false;
      remaining -= metrics.gap + lineHeight;
      return true;
    }

    final showsMeta = !veryNarrow && take(metrics.metaLine);
    final showsTitle = !narrow && take(metrics.metaLine);
    // The instructor is offered a line before the title is allowed a second
    // one, so a long title never crowds out who is teaching.
    final showsInstructor = !narrow && take(metrics.metaLine);
    final titleMaxLines = showsTitle && take(metrics.metaLine) ? 2 : 1;

    return _ContentPlan(
      showsTitle: showsTitle,
      titleMaxLines: titleMaxLines,
      showsMeta: showsMeta,
      showsInstructor: showsInstructor,
    );
  }
}
