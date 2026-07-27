import '../../constants/app_constants.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';

/// A run of consecutive hours taught by one section on one day.
///
/// [TimetableSlot] already carries `hours: [2, 3]` for a two-hour lab — the old
/// grid discarded that and painted one full cell per hour, so a three-hour lab
/// rendered as three stacked boxes each repeating the code, title, instructor
/// and room. Collapsing the run into a single block is what lets the grid read
/// like a calendar instead of a spreadsheet.
class CourseBlock {
  const CourseBlock({
    required this.day,
    required this.startHour,
    required this.endHour,
    required this.slot,
  });

  final DayOfWeek day;
  final int startHour;

  /// Inclusive.
  final int endHour;

  final TimetableSlot slot;

  int get span => endHour - startHour + 1;

  /// Identifies the *section*, so every block of the same section highlights
  /// together.
  String get sectionKey => '${slot.courseCode}-${slot.sectionId}';

  /// e.g. `9:00-10:50 AM`. [TimeSlotInfo.getHourRangeName] sorts its argument
  /// in place, so it is handed a throwaway list.
  String get timeRangeLabel => TimeSlotInfo.getHourRangeName(
    [for (int h = startHour; h <= endHour; h++) h],
  );
}

/// A block and the share of its cell it should occupy, so two sections meeting
/// at the same hour render as two narrower cards rather than one hiding the
/// other. [lane] is the 0-based position across the cell, [laneCount] how many
/// ways the cell is split.
class LaidOutBlock {
  const LaidOutBlock({
    required this.block,
    required this.lane,
    required this.laneCount,
  });

  final CourseBlock block;
  final int lane;
  final int laneCount;
}

/// A section's hours on one day, keyed while building so a section split across
/// several slots still merges into one run.
class _SectionHours {
  _SectionHours(this.slot);

  final TimetableSlot slot;
  final Set<int> hours = {};
}

/// The grid's view of a week: blocks indexed for O(1) lookup, plus the hours and
/// days actually worth drawing.
class TimetableBlockMap {
  TimetableBlockMap._(this._byDay, this.occupiedHours, this.occupiedDays);

  final Map<DayOfWeek, List<CourseBlock>> _byDay;

  /// Hours that hold at least one class, across all days.
  final Set<int> occupiedHours;

  /// Days that hold at least one class.
  final Set<DayOfWeek> occupiedDays;

  static const int firstHour = ScheduleConstants.firstHour;
  static const int lastHour = 12;

  factory TimetableBlockMap.fromSlots(List<TimetableSlot> slots) {
    // Hours are collected per section, not per cell. The grid used to keep one
    // slot per cell (last write wins), which silently erased one of two
    // sections sharing an hour — with the editor's section-clash bypass that is
    // a normal state, and both courses have to stay on the grid.
    final byDaySection = <DayOfWeek, Map<String, _SectionHours>>{};
    for (final slot in slots) {
      final sections = byDaySection.putIfAbsent(slot.day, () => {});
      final entry = sections.putIfAbsent(
        '${slot.courseCode}-${slot.sectionId}',
        () => _SectionHours(slot),
      );
      for (final hour in slot.hours) {
        if (hour < firstHour || hour > lastHour) continue;
        entry.hours.add(hour);
      }
    }

    final byDay = <DayOfWeek, List<CourseBlock>>{};
    final occupiedHours = <int>{};
    final occupiedDays = <DayOfWeek>{};

    for (final entry in byDaySection.entries) {
      final day = entry.key;
      final blocks = <CourseBlock>[];

      for (final section in entry.value.values) {
        final hours = section.hours.toList()..sort();
        for (int i = 0; i < hours.length;) {
          // Extend while the next hour is contiguous with this run.
          int end = i;
          while (end + 1 < hours.length && hours[end + 1] == hours[end] + 1) {
            end++;
          }
          blocks.add(CourseBlock(
            day: day,
            startHour: hours[i],
            endHour: hours[end],
            slot: section.slot,
          ));
          occupiedHours.addAll(hours.getRange(i, end + 1));
          i = end + 1;
        }
      }

      if (blocks.isNotEmpty) {
        blocks.sort((a, b) => a.startHour.compareTo(b.startHour));
        byDay[day] = blocks;
        occupiedDays.add(day);
      }
    }

    return TimetableBlockMap._(byDay, occupiedHours, occupiedDays);
  }

  /// Assigns each of a day's blocks a side-by-side lane, so overlapping
  /// sections split their cell instead of one hiding the other.
  ///
  /// Blocks that overlap — directly or through a chain of overlaps — share a
  /// lane count, which keeps a cluster's cards the same width and their edges
  /// aligned. Blocks that overlap nothing stay full width.
  static List<LaidOutBlock> layOut(List<CourseBlock> dayBlocks) {
    final sorted = [...dayBlocks]
      ..sort((a, b) => a.startHour.compareTo(b.startHour));

    final result = <LaidOutBlock>[];
    var cluster = <CourseBlock>[];
    var clusterEnd = 0;

    void flush() {
      if (cluster.isEmpty) return;
      // Greedy: reuse the first lane whose last block has already ended.
      final laneEnds = <int>[];
      final lanes = <int>[];
      for (final block in cluster) {
        var lane = laneEnds.indexWhere((end) => end < block.startHour);
        if (lane < 0) {
          laneEnds.add(block.endHour);
          lane = laneEnds.length - 1;
        } else {
          laneEnds[lane] = block.endHour;
        }
        lanes.add(lane);
      }
      for (int i = 0; i < cluster.length; i++) {
        result.add(LaidOutBlock(
          block: cluster[i],
          lane: lanes[i],
          laneCount: laneEnds.length,
        ));
      }
      cluster = [];
    }

    for (final block in sorted) {
      if (cluster.isNotEmpty && block.startHour > clusterEnd) flush();
      clusterEnd = cluster.isEmpty
          ? block.endHour
          : (block.endHour > clusterEnd ? block.endHour : clusterEnd);
      cluster.add(block);
    }
    flush();

    return result;
  }

  List<CourseBlock> blocksFor(DayOfWeek day) => _byDay[day] ?? const [];

  /// [blocksFor], each block carrying the lane it should occupy. Computed once
  /// per day and kept, since the grid asks for it on every build and the
  /// geometry pass asks for [maxLaneCount] on top of that.
  List<LaidOutBlock> laidOutFor(DayOfWeek day) =>
      _laidOut[day] ??= layOut(blocksFor(day));

  final Map<DayOfWeek, List<LaidOutBlock>> _laidOut = {};

  /// The widest split anywhere in the week — 1 when nothing clashes. The grid
  /// sizes cells against this so a lane never shrinks below a legible card.
  int get maxLaneCount {
    var max = 1;
    for (final day in _byDay.keys) {
      for (final laid in laidOutFor(day)) {
        if (laid.laneCount > max) max = laid.laneCount;
      }
    }
    return max;
  }

  bool get isEmpty => _byDay.isEmpty;

  /// Course codes in order of first appearance, which is the order the palette
  /// assigns accents in.
  List<String> get courseCodesInOrder {
    final seen = <String>[];
    for (final day in DayOfWeek.values) {
      for (final block in blocksFor(day)) {
        if (!seen.contains(block.slot.courseCode)) {
          seen.add(block.slot.courseCode);
        }
      }
    }
    return seen;
  }

  /// Hours to draw: hour 1 through the last hour anyone actually has a class.
  ///
  /// The start is fixed at 8:00 AM so the grid keeps a stable top anchor —
  /// cropping the start would slide every class down the moment an early
  /// lecture is added. The tail follows the real timetable, so a student whose
  /// week ends at 2 PM gets a seven-row grid instead of twelve rows of mostly
  /// nothing. `showAll` restores the full 8 AM–7:50 PM day.
  List<int> visibleHours({required bool showAll}) {
    if (showAll || occupiedHours.isEmpty) {
      return [for (int h = firstHour; h <= lastHour; h++) h];
    }
    final last = occupiedHours.reduce((a, b) => a > b ? a : b);
    return [for (int h = firstHour; h <= last; h++) h];
  }

  /// Days to draw: Monday through the last day holding a class.
  ///
  /// Only the tail is trimmed. Dropping a mid-week empty day would put Monday
  /// next to Wednesday, which reads as a missing column rather than as a free
  /// day, so an unused Tuesday keeps its place while an unused Saturday — or
  /// Friday and Saturday together — goes. That still buys back most of the
  /// width, since the empty days are usually at the end.
  ///
  /// An empty timetable falls back to Monday–Friday so there is a week-shaped
  /// thing to drop courses into.
  List<DayOfWeek> visibleDays({required bool showAll}) {
    if (showAll) return DayOfWeek.values;
    if (occupiedDays.isEmpty) {
      return [for (final day in DayOfWeek.values) if (day != DayOfWeek.S) day];
    }
    var last = 0;
    for (var i = 0; i < DayOfWeek.values.length; i++) {
      if (occupiedDays.contains(DayOfWeek.values[i])) last = i;
    }
    return DayOfWeek.values.sublist(0, last + 1);
  }
}
