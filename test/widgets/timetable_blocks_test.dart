import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/widgets/timetable/timetable_blocks.dart';

void main() {
  TimetableSlot slot({
    required DayOfWeek day,
    required List<int> hours,
    String code = 'CS F111',
    String section = 'L1',
  }) =>
      TimetableSlot(
        day: day,
        hours: hours,
        courseCode: code,
        courseTitle: 'Computer Programming',
        sectionId: section,
        instructor: 'Dr. A',
        room: '6101',
      );

  group('block merging', () {
    test('collapses a contiguous run into one block', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2, 3, 4]),
      ]);

      final blocks = map.blocksFor(DayOfWeek.M);
      expect(blocks, hasLength(1));
      expect(blocks.single.startHour, 2);
      expect(blocks.single.endHour, 4);
      expect(blocks.single.span, 3);
    });

    test('splits a non-contiguous run into separate blocks', () {
      // A section that meets 9 AM and again at 2 PM on the same day is two
      // classes, not one four-hour block.
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.T, hours: [2, 7]),
      ]);

      final blocks = map.blocksFor(DayOfWeek.T);
      expect(blocks, hasLength(2));
      expect(blocks.map((b) => b.startHour), [2, 7]);
      expect(blocks.every((b) => b.span == 1), isTrue);
    });

    test('does not merge adjacent hours belonging to different sections', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.W, hours: [3], code: 'CS F111'),
        slot(day: DayOfWeek.W, hours: [4], code: 'MATH F112'),
      ]);

      final blocks = map.blocksFor(DayOfWeek.W);
      expect(blocks, hasLength(2));
      expect(blocks.every((b) => b.span == 1), isTrue);
    });

    test('does not merge adjacent hours of different sections of one course',
        () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.W, hours: [3], section: 'L1'),
        slot(day: DayOfWeek.W, hours: [4], section: 'P1'),
      ]);

      expect(map.blocksFor(DayOfWeek.W), hasLength(2));
    });

    test('keeps days independent', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [4]),
        slot(day: DayOfWeek.Th, hours: [4]),
      ]);

      expect(map.blocksFor(DayOfWeek.M), hasLength(1));
      expect(map.blocksFor(DayOfWeek.Th), hasLength(1));
      expect(map.blocksFor(DayOfWeek.T), isEmpty);
    });

    test('resolves overlapping slots instead of producing colliding blocks', () {
      // Clash detection should prevent this, but a hand-edited import can still
      // land two sections on one cell; the grid must stay renderable.
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.F, hours: [5], code: 'CS F111'),
        slot(day: DayOfWeek.F, hours: [5], code: 'PHY F110'),
      ]);

      final blocks = map.blocksFor(DayOfWeek.F);
      expect(blocks, hasLength(1));
      expect(blocks.single.slot.courseCode, 'PHY F110'); // last write wins
    });

    test('ignores hours outside the 1-12 grid', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [0, 1, 13]),
      ]);

      final blocks = map.blocksFor(DayOfWeek.M);
      expect(blocks, hasLength(1));
      expect(blocks.single.startHour, 1);
      expect(blocks.single.endHour, 1);
    });

    test('labels a merged block with its full time range', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2, 3]),
      ]);

      expect(map.blocksFor(DayOfWeek.M).single.timeRangeLabel, '9:00-10:50 AM');
    });
  });

  group('cropping', () {
    test('ends at the last hour anyone actually has a class', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
      ]);

      expect(map.visibleHours(showAll: false), [1, 2]);
    });

    test('takes the latest hour across the whole week, not per day', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
        slot(day: DayOfWeek.Th, hours: [7], code: 'MATH F112'),
      ]);

      expect(map.visibleHours(showAll: false).last, 7);
    });

    test('extends to the end of the day for a late class', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [12]),
      ]);

      expect(map.visibleHours(showAll: false).last, 12);
    });

    test('always anchors at hour 1 so classes do not shift', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [9]),
      ]);

      expect(map.visibleHours(showAll: false).first, 1);
    });

    test('showAll restores the full twelve hours', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
      ]);

      expect(map.visibleHours(showAll: true), hasLength(12));
    });

    test('ends at the last day holding a class', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
        slot(day: DayOfWeek.W, hours: [3], code: 'MATH F112'),
      ]);

      expect(map.visibleDays(showAll: false), [
        DayOfWeek.M,
        DayOfWeek.T,
        DayOfWeek.W,
      ]);
    });

    test('keeps a free mid-week day in place', () {
      // Removing it would put Monday next to Wednesday, which reads as a
      // missing column rather than as a free day.
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
        slot(day: DayOfWeek.F, hours: [3], code: 'MATH F112'),
      ]);

      expect(map.visibleDays(showAll: false), hasLength(5));
      expect(map.visibleDays(showAll: false).last, DayOfWeek.F);
    });

    test('keeps Saturday when it holds a class', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.S, hours: [2]),
      ]);

      expect(map.visibleDays(showAll: false), hasLength(6));
    });

    test('drops Friday and Saturday together when both are free', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.Th, hours: [2]),
      ]);

      expect(map.visibleDays(showAll: false), hasLength(4));
    });

    test('showAll restores the whole week', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2]),
      ]);

      expect(map.visibleDays(showAll: true), hasLength(6));
    });

    test('an empty timetable still shows a week-shaped grid', () {
      // Nothing to crop against, and a collapsed grid gives courses nowhere to
      // land.
      final map = TimetableBlockMap.fromSlots([]);

      expect(map.isEmpty, isTrue);
      expect(map.visibleHours(showAll: false), hasLength(12));
      expect(map.visibleDays(showAll: false), hasLength(5));
    });
  });

  group('course ordering', () {
    test('reports distinct course codes for palette assignment', () {
      final map = TimetableBlockMap.fromSlots([
        slot(day: DayOfWeek.M, hours: [2], code: 'CS F111'),
        slot(day: DayOfWeek.T, hours: [2], code: 'CS F111'),
        slot(day: DayOfWeek.W, hours: [3], code: 'MATH F112'),
      ]);

      expect(map.courseCodesInOrder, ['CS F111', 'MATH F112']);
    });
  });
}
