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

/// The grid's view of a week: blocks indexed for O(1) lookup, plus the hours and
/// days actually worth drawing.
class TimetableBlockMap {
  TimetableBlockMap._(this._byDay, this.occupiedHours, this.occupiedDays);

  final Map<DayOfWeek, List<CourseBlock>> _byDay;

  /// Hours that hold at least one class, across all days.
  final Set<int> occupiedHours;

  /// Days that hold at least one class.
  final Set<DayOfWeek> occupiedDays;

  static const int firstHour = 1;
  static const int lastHour = 12;

  factory TimetableBlockMap.fromSlots(List<TimetableSlot> slots) {
    // Resolve overlaps first, exactly as the old grid did (last write wins), so
    // a malformed import can never produce two blocks fighting for one cell.
    final grid = <DayOfWeek, Map<int, TimetableSlot>>{};
    for (final slot in slots) {
      final day = grid.putIfAbsent(slot.day, () => <int, TimetableSlot>{});
      for (final hour in slot.hours) {
        if (hour < firstHour || hour > lastHour) continue;
        day[hour] = slot;
      }
    }

    final byDay = <DayOfWeek, List<CourseBlock>>{};
    final occupiedHours = <int>{};
    final occupiedDays = <DayOfWeek>{};

    for (final entry in grid.entries) {
      final day = entry.key;
      final hours = entry.value;
      final blocks = <CourseBlock>[];

      int hour = firstHour;
      while (hour <= lastHour) {
        final slot = hours[hour];
        if (slot == null) {
          hour++;
          continue;
        }
        // Extend while the next hour is the same section on the same day.
        int end = hour;
        while (end + 1 <= lastHour && _isSameSection(hours[end + 1], slot)) {
          end++;
        }
        blocks.add(
          CourseBlock(day: day, startHour: hour, endHour: end, slot: slot),
        );
        for (int h = hour; h <= end; h++) {
          occupiedHours.add(h);
        }
        occupiedDays.add(day);
        hour = end + 1;
      }

      if (blocks.isNotEmpty) byDay[day] = blocks;
    }

    return TimetableBlockMap._(byDay, occupiedHours, occupiedDays);
  }

  static bool _isSameSection(TimetableSlot? a, TimetableSlot? b) {
    if (a == null || b == null) return false;
    return a.courseCode == b.courseCode && a.sectionId == b.sectionId;
  }

  List<CourseBlock> blocksFor(DayOfWeek day) => _byDay[day] ?? const [];

  /// The block starting exactly at [hour], or null.
  CourseBlock? blockStartingAt(DayOfWeek day, int hour) {
    for (final block in blocksFor(day)) {
      if (block.startHour == hour) return block;
    }
    return null;
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
