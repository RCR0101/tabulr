import '../models/course.dart';

enum CalendarPeriod { classes, midsem, endsem }

int calendarDayIndex(DateTime date) => date.weekday - DateTime.monday;

DayOfWeek? calendarDayForIndex(int index) =>
    index >= 0 && index < DayOfWeek.values.length
        ? DayOfWeek.values[index]
        : null;

CalendarPeriod calendarPeriodForDate(
  DateTime date, {
  required DateTime midsemStart,
  required DateTime midsemEnd,
  required DateTime endsemStart,
  required DateTime endsemEnd,
}) {
  if (!date.isBefore(midsemStart) && !date.isAfter(midsemEnd)) {
    return CalendarPeriod.midsem;
  }
  if (!date.isBefore(endsemStart) && !date.isAfter(endsemEnd)) {
    return CalendarPeriod.endsem;
  }
  return CalendarPeriod.classes;
}
