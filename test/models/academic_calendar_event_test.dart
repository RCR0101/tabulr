import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';

void main() {
  group('AcademicCalendarEvent', () {
    test('round-trips through JSON, including an optional end date', () {
      final e = AcademicCalendarEvent(
        date: DateTime(2026, 3, 9),
        endDate: DateTime(2026, 3, 14),
        label: 'Mid Semester Exams',
        category: AcademicEventCategory.exam,
        dayOfWeek: 'M',
      );
      final back = AcademicCalendarEvent.fromJson(e.toJson());
      expect(back.date, e.date);
      expect(back.endDate, e.endDate);
      expect(back.label, 'Mid Semester Exams');
      expect(back.category, AcademicEventCategory.exam);
      expect(back.dayOfWeek, 'M');
      expect(back.isRange, isTrue);
    });

    test('a single-day entry serialises without an endDate key', () {
      final e = AcademicCalendarEvent(
        date: DateTime(2026, 1, 26),
        label: 'Republic Day (H)',
        category: AcademicEventCategory.holiday,
      );
      expect(e.toJson().containsKey('endDate'), isFalse);
      expect(e.isRange, isFalse);
    });

    test('coversDay is inclusive across a range and excludes outside days', () {
      final e = AcademicCalendarEvent(
        date: DateTime(2026, 5, 2),
        endDate: DateTime(2026, 5, 16),
        label: 'Comprehensive Examination',
        category: AcademicEventCategory.exam,
      );
      expect(e.coversDay(DateTime(2026, 5, 2, 9)), isTrue); // start, with time
      expect(e.coversDay(DateTime(2026, 5, 10)), isTrue); // middle
      expect(e.coversDay(DateTime(2026, 5, 16)), isTrue); // inclusive end
      expect(e.coversDay(DateTime(2026, 5, 1)), isFalse); // before
      expect(e.coversDay(DateTime(2026, 5, 17)), isFalse); // after
    });

    test('unknown category names fall back to event', () {
      expect(AcademicEventCategory.fromName('nonsense'),
          AcademicEventCategory.event);
      expect(AcademicEventCategory.fromName(null), AcademicEventCategory.event);
      expect(AcademicEventCategory.fromName('deadline'),
          AcademicEventCategory.deadline);
    });

    test('only deadlines and exams are reminder-worthy', () {
      expect(AcademicEventCategory.deadline.isReminderWorthy, isTrue);
      expect(AcademicEventCategory.exam.isReminderWorthy, isTrue);
      expect(AcademicEventCategory.holiday.isReminderWorthy, isFalse);
      expect(AcademicEventCategory.milestone.isReminderWorthy, isFalse);
      expect(AcademicEventCategory.event.isReminderWorthy, isFalse);
    });
  });
}
