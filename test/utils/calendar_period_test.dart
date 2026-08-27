import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/utils/calendar_period.dart';

void main() {
  group('calendar day mapping', () {
    test('maps Friday to the timetable Friday enum', () {
      final friday = DateTime(2026, 8, 28);

      expect(calendarDayIndex(friday), 4);
      expect(calendarDayForIndex(calendarDayIndex(friday)), DayOfWeek.F);
    });

    test('keeps Sunday selectable but outside recurring timetable days', () {
      final sunday = DateTime(2026, 8, 30);

      expect(calendarDayIndex(sunday), 6);
      expect(calendarDayForIndex(calendarDayIndex(sunday)), isNull);
    });
  });

  group('calendar period', () {
    CalendarPeriod period(DateTime date) => calendarPeriodForDate(
      date,
      midsemStart: DateTime(2026, 3, 9),
      midsemEnd: DateTime(2026, 3, 14),
      endsemStart: DateTime(2026, 5, 2),
      endsemEnd: DateTime(2026, 5, 16),
    );

    test('shows recurring classes outside stale semester boundaries', () {
      expect(period(DateTime(2026, 8, 28)), CalendarPeriod.classes);
    });

    test('exam ranges remain inclusive', () {
      expect(period(DateTime(2026, 3, 9)), CalendarPeriod.midsem);
      expect(period(DateTime(2026, 3, 14)), CalendarPeriod.midsem);
      expect(period(DateTime(2026, 5, 16)), CalendarPeriod.endsem);
    });
  });
}
