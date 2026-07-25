import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_calendar_event.dart';
import 'package:timetable_maker/widgets/academic_calendar_list.dart';

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

Future<void> _pump(WidgetTester tester, List<AcademicCalendarEvent> events) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AcademicCalendarAgenda(events: events)),
  ));
}

void main() {
  final past = AcademicCalendarEvent(
    date: _day(-10),
    label: 'Classwork begins',
    category: AcademicEventCategory.milestone,
  );
  final holiday = AcademicCalendarEvent(
    date: _day(3),
    label: 'Independence Day',
    category: AcademicEventCategory.holiday,
  );
  final deadline = AcademicCalendarEvent(
    date: _day(8),
    label: 'Last date to drop a course',
    category: AcademicEventCategory.deadline,
  );
  // Started yesterday, ends in three days — still current, not past.
  final ongoing = AcademicCalendarEvent(
    date: _day(-1),
    endDate: _day(3),
    label: 'Mid-semester examinations',
    category: AcademicEventCategory.exam,
  );

  testWidgets('past entries are hidden until asked for', (tester) async {
    await _pump(tester, [past, holiday]);

    expect(find.text('Independence Day'), findsOneWidget);
    expect(find.text('Classwork begins'), findsNothing);

    await tester.tap(find.text('Show past (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Classwork begins'), findsOneWidget);
    expect(find.text('Independence Day'), findsOneWidget);
  });

  testWidgets('a run that covers today counts as current, not past',
      (tester) async {
    await _pump(tester, [ongoing]);

    expect(find.text('Mid-semester examinations'), findsOneWidget);
    expect(find.text('On now'), findsOneWidget);
    // Nothing is past, so the toggle has no reason to exist.
    expect(find.textContaining('Show past'), findsNothing);
  });

  testWidgets('a category chip narrows the list to that category',
      (tester) async {
    await _pump(tester, [holiday, deadline]);

    expect(find.text('Independence Day'), findsOneWidget);
    expect(find.text('Last date to drop a course'), findsOneWidget);

    // The chip and the row's category pill share the word, so target the chip.
    await tester.tap(find.widgetWithText(FilterChip, 'Holiday'));
    await tester.pumpAndSettle();

    expect(find.text('Independence Day'), findsOneWidget);
    expect(find.text('Last date to drop a course'), findsNothing);
  });

  testWidgets('countdown is in plain words', (tester) async {
    await _pump(tester, [
      AcademicCalendarEvent(
        date: _day(0),
        label: 'Grading day',
        category: AcademicEventCategory.milestone,
      ),
      AcademicCalendarEvent(
        date: _day(1),
        label: 'Holi',
        category: AcademicEventCategory.holiday,
      ),
      deadline,
    ]);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('in 8 days'), findsOneWidget);
  });

  testWidgets('empty calendar explains itself', (tester) async {
    await _pump(tester, []);
    expect(find.text('No academic calendar yet'), findsOneWidget);
    // The empty state animates in; let its tickers finish before teardown.
    await tester.pumpAndSettle();
  });
}
