import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';
import '../../models/app_theme.dart';
import '../../models/timetable_display.dart';
import '../../utils/datetime_utils.dart';
import 'course_palette.dart';
import 'timetable_blocks.dart';

/// Which cell fields a block should render. Enumerated rather than
/// stringly-keyed so an unknown field is a compile error, not a silent no-op.
enum TimetableField { courseCode, courseTitle, sectionId, instructor, room }

/// The week grid.
///
/// Two invariants drive the whole layout:
///
///  * **Columns divide the available width.** Column width is measured from the
///    viewport; only a viewport too narrow for a legible minimum falls back to
///    horizontal scrolling.
///  * **Row height is the only thing density controls**, and
///    [TimetableSize.fit] derives it from the viewport so the entire grid is
///    visible at once.
///
/// Headers are pinned on both axes: panning never loses the time column or the
/// day names.
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
    this.alternatives,
    this.onSectionSwap,
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

  /// Catalogue courses, so a long-pressed block can show where the course's
  /// other sections of the same kind would sit. Null disables ghost mode.
  final List<Course>? alternatives;

  /// Fired when a ghost section is tapped; the host swaps [fromSectionId] for
  /// [toSectionId] on [courseCode].
  final void Function(
    String courseCode,
    String fromSectionId,
    String toSectionId,
  )? onSectionSwap;

  // Export geometry, kept in one place so it can't drift from
  // [_TimetableGridState._measure] (which uses these) and so the export surface
  // can size the exam-schedule table to the grid's own width.
  static const double _verticalLeadWidth = 62.0;
  static double exportColumnExtent(double rowExtent) =>
      (rowExtent * 2.0).clamp(150.0, 300.0);

  /// Natural rendered width of the grid in export mode: vertical layout, no
  /// text scaling, cropped to the occupied days. Lets the export surface make
  /// the exam-schedule table exactly as wide as the timetable.
  static double exportContentWidth({
    required List<TimetableSlot> slots,
    required TimetableSize size,
  }) {
    final blocks = TimetableBlockMap.fromSlots(slots);
    final days = blocks.visibleDays(showAll: false);
    final rowExtent = (size.fixedRowHeight ?? 84.0).clamp(34.0, 132.0);
    return _verticalLeadWidth +
        exportColumnExtent(rowExtent) * blocks.maxLaneCount * days.length;
  }

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<_GridFocus> _focus = ValueNotifier(const _GridFocus());

  /// Drives the outline on clashing blocks. Started only while a clash exists,
  /// so a clean week never ticks. Built in [initState] rather than lazily: a
  /// `late final` initialiser runs on first *access*, and on a clash-free week
  /// the first access is `dispose()` — which then creates a ticker against an
  /// already-deactivated element and aborts the rest of the teardown.
  late final AnimationController _pulse;
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _headerHorizontal = ScrollController();
  Timer? _dayTicker;
  DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _bodyHorizontal.addListener(_syncHeaderScroll);
    if (!widget.isForExport) {
      // The current-time line owns its own ticker (_NowIndicator); advancing it
      // here rebuilt every day column and course block once a minute. All this
      // needs is to refresh the "today" highlight when the date rolls over.
      _dayTicker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) return;
        final now = DateTime.now();
        if (now.day != _today.day ||
            now.month != _today.month ||
            now.year != _today.year) {
          setState(() => _today = now);
        }
      });
    }
  }

  @override
  void dispose() {
    _dayTicker?.cancel();
    _pulse.dispose();
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
    _focus.value = _focus.value.copyWith(
      selectedKey: sectionKey,
      clearSelected: sectionKey == null,
      clearGhost: sectionKey == null,
    );
  }

  bool get _canGhost =>
      !widget.isForExport &&
      widget.alternatives != null &&
      widget.onSectionSwap != null;

  /// Long-pressing a block shows where the course's other sections of the same
  /// kind meet; pressing the same block again puts them away.
  void _toggleGhosts(CourseBlock block) {
    if (!_canGhost) return;
    final key = block.sectionKey;
    final already = _focus.value.ghostKey == key;
    _focus.value = _focus.value.copyWith(
      selectedKey: already ? null : key,
      clearSelected: already,
      ghostKey: already ? null : key,
      clearGhost: already,
    );
  }

  /// Sections of [block]'s course with the same type, other than its own.
  List<Section> _alternativesFor(CourseBlock block) {
    final course = widget.alternatives
        ?.where((c) => c.courseCode == block.slot.courseCode)
        .firstOrNull;
    if (course == null) return const [];
    final own = course.sections
        .where((s) => s.sectionId == block.slot.sectionId)
        .firstOrNull;
    if (own == null) return const [];
    return [
      for (final s in course.sections)
        if (s.type == own.type && s.sectionId != own.sectionId) s,
    ];
  }

  /// Which sections were clashing the last time the pulse ran, so a rebuild
  /// with the same clashes does not restart it.
  String _pulseSignature = '';

  /// Three breaths, then rest on the highlighted state: enough to draw the eye
  /// without becoming a permanent distraction, and finite so the frame
  /// scheduler (and `pumpAndSettle`) can go idle.
  void _syncPulse(TimetableBlockMap blocks) {
    final clashing = <String>{
      for (final day in DayOfWeek.values)
        for (final laid in blocks.laidOutFor(day))
          if (laid.laneCount > 1) laid.block.sectionKey,
    };
    final signature = (clashing.toList()..sort()).join(',');
    if (signature == _pulseSignature) return;
    _pulseSignature = signature;
    _pulse.stop();
    if (clashing.isEmpty || widget.isForExport) {
      _pulse.value = 0;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else {
      _pulse.value = 0;
      _pulse.repeat(reverse: true, count: 3);
    }
  }

  TextScaler get _textScaler =>
      widget.isForExport ? TextScaler.noScaling : MediaQuery.textScalerOf(context);

  bool get _isTouch =>
      !widget.isForExport && MediaQuery.maybeOf(context) != null &&
      MediaQuery.sizeOf(context).width <= ResponsiveConstants.tabletBreakpoint;

  @override
  Widget build(BuildContext context) {
    final blocks = TimetableBlockMap.fromSlots(widget.slots);
    _syncPulse(blocks);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _measure(constraints, blocks);
        final body = widget.isForExport
            ? _buildBody(context, blocks, geometry)
            : Stack(
                children: [
                  _buildBody(context, blocks, geometry),
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: _ghostBanner(context, blocks),
                  ),
                ],
              );

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

    final leadWidth = (vertical ? TimetableGrid._verticalLeadWidth : 78.0) * scale;
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

    // A clash splits a cell between two cards, so a cell that was merely small
    // becomes an illegible sliver. Sizing against the widest split keeps each
    // lane as big as an unsplit cell would have been; on a narrow viewport that
    // trades into horizontal scrolling, which beats blank coloured bars.
    // Only the cross axis of a block is split: the day column in the vertical
    // layout, the day row in the horizontal one.
    final lanes = blocks.maxLaneCount;
    if (!vertical) row = (row * lanes).clamp(34.0, maxRow * lanes);

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
        columnExtent:
            TimetableGrid.exportColumnExtent(row) * (vertical ? lanes : 1),
        rowExtent: row,
        needsHorizontalScroll: false,
      );
    }

    final available = (constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0) - leadWidth;
    final minColumn =
        (vertical ? (_isTouch ? 84.0 : 96.0) * lanes : 62.0 * scale);

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
    final isToday = !widget.isForExport && day == _todayOfWeek(_today);
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
                          color: geo.days[index] == _todayOfWeek(_today) && !widget.isForExport
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
          // Static for a given geometry — keep them off the blocks' layer.
          Positioned.fill(
            child: RepaintBoundary(
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
          ),
          if (geo.vertical)
            Row(
              children: [
                for (final day in geo.days)
                  SizedBox(
                    width: geo.columnExtent,
                    child: _dayBlocks(context, blocks, geo, day),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final day in geo.days)
                  SizedBox(
                    height: geo.rowExtent,
                    child: _dayBlocks(context, blocks, geo, day),
                  ),
              ],
            ),
          if (!widget.isForExport)
            _NowIndicator(
              geo: geo,
              color: scheme.error.withValues(alpha: 0.7),
            ),
        ],
      ),
    );
  }

  /// One day's cards, positioned along the hour axis and across the lanes
  /// [TimetableBlockMap.layOut] assigned. Both layouts share this: vertical
  /// runs hours down and lanes across the column, horizontal swaps the two.
  ///
  /// Positioning rather than laying children out in sequence is what lets two
  /// clashing sections sit side by side in the same cell — each still a normal
  /// card, just narrower.
  Widget _dayBlocks(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
    DayOfWeek day,
  ) {
    final firstHour = geo.hours.first;
    final lastHour = geo.hours.last;
    final children = <Widget>[];

    for (final laid in blocks.laidOutFor(day)) {
      final block = laid.block;
      if (block.startHour < firstHour || block.startHour > lastHour) continue;
      // Clamp against the visible tail so a cropped grid cannot overflow.
      final span = block.endHour.clamp(block.startHour, lastHour) -
          block.startHour +
          1;
      final along = (block.startHour - firstHour).toDouble();
      final share = 1.0 / laid.laneCount;

      if (geo.vertical) {
        final width = geo.columnExtent * share;
        final height = geo.rowExtent * span;
        children.add(Positioned(
          top: along * geo.rowExtent,
          left: laid.lane * width,
          width: width,
          height: height,
          child: _buildBlock(context, block, width, height, laid.laneCount),
        ));
      } else {
        final width = geo.columnExtent * span;
        final height = geo.rowExtent * share;
        children.add(Positioned(
          left: along * geo.columnExtent,
          top: laid.lane * height,
          width: width,
          height: height,
          child: _buildBlock(context, block, width, height, laid.laneCount),
        ));
      }
    }

    // Ghosts live under their own listener: the column is built once per
    // layout, and entering ghost mode only pokes the focus notifier.
    if (_canGhost) {
      children.add(Positioned.fill(
        child: ValueListenableBuilder<_GridFocus>(
          valueListenable: _focus,
          builder: (context, focus, _) => focus.ghostKey == null
              ? const SizedBox.shrink()
              : Stack(children: _ghostBlocks(context, blocks, geo, day)),
        ),
      ));
    }
    return Stack(children: children);
  }

  // ── Ghost sections ────────────────────────────────────────────────────────

  /// The block whose alternatives are showing, if any.
  CourseBlock? _ghostSource(TimetableBlockMap blocks) {
    final key = _focus.value.ghostKey;
    if (key == null) return null;
    for (final day in DayOfWeek.values) {
      for (final laid in blocks.laidOutFor(day)) {
        if (laid.block.sectionKey == key) return laid.block;
      }
    }
    return null;
  }

  Widget _ghostBanner(BuildContext context, TimetableBlockMap blocks) {
    return ValueListenableBuilder<_GridFocus>(
      valueListenable: _focus,
      builder: (context, focus, _) {
        final source = _ghostSource(blocks);
        if (source == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final count = _alternativesFor(source).length;
        final label = count == 0
            ? 'No other ${source.slot.sectionId[0]} sections for ${source.slot.courseCode}'
            : 'Other sections of ${source.slot.courseCode} · tap one to switch';
        return Center(
          child: Material(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(ThemeGeometry.of(context).chipRadius),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      size: 16, color: scheme.onInverseSurface),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onInverseSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Hide other sections',
                    color: scheme.onInverseSurface,
                    onPressed: () => _selectSection(null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Translucent dashed cards for every alternative section meeting on [day].
  /// Red when the alternative would collide with something already placed.
  List<Widget> _ghostBlocks(
    BuildContext context,
    TimetableBlockMap blocks,
    _GridGeometry geo,
    DayOfWeek day,
  ) {
    final source = _ghostSource(blocks);
    if (source == null) return const [];
    final firstHour = geo.hours.first;
    final lastHour = geo.hours.last;
    final accent = widget.palette.colorFor(source.slot.courseCode);
    final occupied = <int>{
      for (final laid in blocks.laidOutFor(day))
        if (laid.block.sectionKey != source.sectionKey)
          for (int h = laid.block.startHour; h <= laid.block.endHour; h++) h,
    };

    final out = <Widget>[];
    for (final section in _alternativesFor(source)) {
      for (final entry in section.schedule) {
        if (!entry.days.contains(day) || entry.hours.isEmpty) continue;
        for (final run in _runs(entry.hours)) {
          final start = run.$1;
          final end = run.$2.clamp(start, lastHour);
          if (start < firstHour || start > lastHour) continue;
          final span = end - start + 1;
          final along = (start - firstHour).toDouble();
          final clashes = [for (int h = start; h <= end; h++) h]
              .any(occupied.contains);
          final card = _GhostCard(
            key: ValueKey('ghost-${section.sectionId}-$day-$start'),
            section: section,
            accent: accent,
            clashes: clashes,
            onTap: () {
              widget.onSectionSwap!(
                source.slot.courseCode,
                source.slot.sectionId,
                section.sectionId,
              );
              _selectSection(null);
            },
          );
          out.add(geo.vertical
              ? Positioned(
                  top: along * geo.rowExtent,
                  left: 0,
                  width: geo.columnExtent,
                  height: geo.rowExtent * span,
                  child: card,
                )
              : Positioned(
                  left: along * geo.columnExtent,
                  top: 0,
                  width: geo.columnExtent * span,
                  height: geo.rowExtent,
                  child: card,
                ));
        }
      }
    }
    return out;
  }

  /// Contiguous runs of a sorted hour list: `[2, 3, 5]` → `(2,3), (5,5)`.
  static List<(int, int)> _runs(List<int> hours) {
    final sorted = [...hours]..sort();
    final runs = <(int, int)>[];
    int start = sorted.first, prev = sorted.first;
    for (final h in sorted.skip(1)) {
      if (h == prev + 1) {
        prev = h;
        continue;
      }
      runs.add((start, prev));
      start = prev = h;
    }
    runs.add((start, prev));
    return runs;
  }

  // ── Block card ────────────────────────────────────────────────────────────

  Widget _buildBlock(
    BuildContext context,
    CourseBlock block,
    double width,
    double height,
    int laneCount,
  ) {
    final accent = widget.palette.colorFor(block.slot.courseCode);
    final warning = _incompleteWarningFor(block.slot.courseCode);
    final clashPulse = laneCount > 1 && !widget.isForExport ? _pulse : null;

    return RepaintBoundary(
      child: ValueListenableBuilder<_GridFocus>(
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
          clashPulse: clashPulse,
          isGhostSource: focus.ghostKey == block.sectionKey,
          onAlternatives: _canGhost ? () => _toggleGhosts(block) : null,
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
      ),
    );
  }

  String? _incompleteWarningFor(String courseCode) {
    final matches = widget.incompleteSelectionWarnings
        .where((warning) => warning.startsWith(courseCode))
        .toList();
    return matches.isEmpty ? null : matches.join('\n');
  }

  // ── Today / now ───────────────────────────────────────────────────────────

  int? _todayColumnIndex(_GridGeometry geo) {
    if (widget.isForExport) return null;
    final today = _todayOfWeek(_today);
    if (today == null) return null;
    final index = geo.days.indexOf(today);
    return index < 0 ? null : index;
  }

}

DayOfWeek? _todayOfWeek(DateTime now) => switch (now.weekday) {
  DateTime.monday => DayOfWeek.M,
  DateTime.tuesday => DayOfWeek.T,
  DateTime.wednesday => DayOfWeek.W,
  DateTime.thursday => DayOfWeek.Th,
  DateTime.friday => DayOfWeek.F,
  DateTime.saturday => DayOfWeek.S,
  _ => null,
};

/// The current-time rule. Owns its own ticker so advancing it repaints only
/// this line, not the grid of course blocks behind it.
class _NowIndicator extends StatefulWidget {
  const _NowIndicator({required this.geo, required this.color});

  final _GridGeometry geo;
  final Color color;

  @override
  State<_NowIndicator> createState() => _NowIndicatorState();
}

class _NowIndicatorState extends State<_NowIndicator> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  /// Distance along the hour axis for the current time, or null when outside
  /// teaching hours. Hour 1 starts at 08:00.
  double? _offset() {
    final geo = widget.geo;
    final today = _todayOfWeek(_now);
    if (today == null || !geo.days.contains(today)) return null;

    final minutesSinceFirstHour = (_now.hour * 60 + _now.minute) - 8 * 60;
    if (minutesSinceFirstHour < 0) return null;

    final hoursElapsed = minutesSinceFirstHour / 60.0;
    if (hoursElapsed > geo.hours.length) return null;

    return hoursElapsed * (geo.vertical ? geo.rowExtent : geo.columnExtent);
  }

  @override
  Widget build(BuildContext context) {
    final offset = _offset();
    if (offset == null) return const SizedBox.shrink();
    final geo = widget.geo;
    return Positioned(
      top: geo.vertical ? offset : 0,
      left: geo.vertical ? 0 : offset,
      width: geo.vertical ? geo.bodyWidth : 1.5,
      height: geo.vertical ? 1.5 : geo.bodyHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: DecoratedBox(decoration: BoxDecoration(color: widget.color)),
        ),
      ),
    );
  }
}

// ── Supporting types ────────────────────────────────────────────────────────

class _GridFocus {
  const _GridFocus({this.hoveredKey, this.selectedKey, this.ghostKey});

  final String? hoveredKey;
  final String? selectedKey;

  /// Section whose alternative sections are drawn as ghosts.
  final String? ghostKey;

  _GridFocus copyWith({
    String? hoveredKey,
    String? selectedKey,
    String? ghostKey,
    bool clearHovered = false,
    bool clearSelected = false,
    bool clearGhost = false,
  }) {
    return _GridFocus(
      hoveredKey: clearHovered ? null : (hoveredKey ?? this.hoveredKey),
      selectedKey: clearSelected ? null : (selectedKey ?? this.selectedKey),
      ghostKey: clearGhost ? null : (ghostKey ?? this.ghostKey),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GridFocus &&
      other.hoveredKey == hoveredKey &&
      other.selectedKey == selectedKey &&
      other.ghostKey == ghostKey;

  @override
  int get hashCode => Object.hash(hoveredKey, selectedKey, ghostKey);
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
    this.clashPulse,
    this.isGhostSource = false,
    this.onAlternatives,
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

  /// Non-null while this block shares its cell with another section.
  final Animation<double>? clashPulse;

  /// True while this block's alternatives are being shown as ghosts.
  final bool isGhostSource;

  /// Long-press (or the hover chip) to show the course's other sections.
  final VoidCallback? onAlternatives;

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
    final showsSwap = onAlternatives != null && (isHovered || isSelected);

    // Follows the theme's card radius, scaled down so a one-hour card at high
    // density is not all corner.
    final themeRadius = ThemeGeometry.of(context).cardRadius;
    final radius = (themeRadius * 0.75).clamp(4.0, height < 44 ? 6.0 : 12.0);
    final restBorder =
        accent.withValues(alpha: isSelected ? 0.6 : (isHovered ? 0.42 : 0.24));

    Widget shell(Widget child) {
      final pulse = clashPulse;
      if (pulse == null) {
        return Container(
          margin: EdgeInsets.all(inset),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isGhostSource ? scheme.primary : restBorder,
              width: isSelected || isGhostSource ? 1.4 : 1.0,
            ),
          ),
          child: child,
        );
      }
      // Clashing blocks breathe between their own accent and the error colour
      // so the collision is findable at a glance without a banner.
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(pulse.value);
          return Container(
            margin: EdgeInsets.all(inset),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Color.lerp(fill, scheme.error.withValues(alpha: 0.14), t),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Color.lerp(restBorder, scheme.error, 0.35 + 0.65 * t)!,
                width: 1.4,
              ),
            ),
            child: child,
          );
        },
        child: child,
      );
    }

    final card = shell(
      Stack(
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
          if (showsSwap)
            Positioned(
              top: 1,
              right: showsRemove ? 22 : 1,
              child: Semantics(
                label: 'Show other sections of ${slot.courseCode}',
                button: true,
                child: Tooltip(
                  message: 'Other sections',
                  child: GestureDetector(
                    onTap: onAlternatives,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.swap_horiz_rounded,
                          size: 12, color: scheme.onPrimary),
                    ),
                  ),
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
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onAlternatives,
          child: card,
        ),
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

/// Where an alternative section would sit: a dashed, translucent card that
/// takes the course's accent when the slot is free and the error colour when it
/// would collide with something already placed.
class _GhostCard extends StatelessWidget {
  const _GhostCard({
    super.key,
    required this.section,
    required this.accent,
    required this.clashes,
    required this.onTap,
  });

  final Section section;
  final Color accent;
  final bool clashes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = clashes ? scheme.error : accent;
    final radius =
        (ThemeGeometry.of(context).cardRadius * 0.75).clamp(4.0, 12.0);
    return Semantics(
      label:
          'Switch to ${section.sectionId}${clashes ? ', clashes' : ''}',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: tint.withValues(alpha: 0.9),
                fill: tint.withValues(alpha: 0.10),
                radius: radius,
              ),
              // A corner pill rather than centred text, so the label stays
              // legible when the ghost sits over a card it would clash with.
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: tint.withValues(alpha: 0.7)),
                  ),
                  child: Text(
                    clashes ? '${section.sectionId} · clash' : section.sectionId,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.fill,
    required this.radius,
  });

  final Color color;
  final Color fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final path = Path()..addRRect(rrect);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), stroke);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius;
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

    // Half a pixel of slack: a line's painted height is the font's own metrics
    // rounded up, not exactly `fontSize * height`, so admitting a line that
    // fits with zero to spare overflowed the card by a quarter of a pixel —
    // enough for a debug stripe and a thrown exception in any fit-mode test.
    const rounding = 0.5;

    bool take(double lineHeight) {
      if (remaining - metrics.gap - lineHeight < rounding) return false;
      remaining -= metrics.gap + lineHeight;
      return true;
    }

    // The title goes first now, ahead of section/room and the instructor. On a
    // phone the cards are narrow enough that the old order dropped the name
    // from most of them, so which courses showed one depended on how wide the
    // day column happened to be — the code alone is exactly what a first-year
    // cannot decode. An ellipsised name still says more than "CS F211".
    final showsTitle = !veryNarrow && take(metrics.metaLine);
    final showsMeta = !veryNarrow && take(metrics.metaLine);
    // The instructor is offered a line before the title is allowed a second
    // one, so a long title never crowds out who is teaching.
    final showsInstructor = !narrow && take(metrics.metaLine);
    final titleMaxLines = showsTitle && !narrow && take(metrics.metaLine) ? 2 : 1;

    return _ContentPlan(
      showsTitle: showsTitle,
      titleMaxLines: titleMaxLines,
      showsMeta: showsMeta,
      showsInstructor: showsInstructor,
    );
  }
}
