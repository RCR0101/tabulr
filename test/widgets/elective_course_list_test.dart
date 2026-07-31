import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_selection_link.dart';
import 'package:timetable_maker/widgets/elective_course_list.dart';

import '../helpers/test_data.dart';

/// Pumps the results list the elective browsers render.
Future<void> pumpList(
  WidgetTester tester, {
  required List<Course> courses,
  List<Course>? catalog,
  TimetableSelectionLink? link,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ElectiveCourseList(
          courses: courses,
          catalog: catalog ?? courses,
          selectionLink: link,
        ),
      ),
    ),
  );
}

/// A link backed by a mutable list, mimicking the editor's live selection.
({TimetableSelectionLink link, List<SelectedSection> sections, ValueNotifier<int> revision})
    makeLink({List<Course> availableCourses = const []}) {
  final sections = <SelectedSection>[];
  final revision = ValueNotifier(0);
  final link = TimetableSelectionLink(
    selectedSections: sections,
    availableCourses: availableCourses,
    revision: revision,
    timetableName: 'Sem 1',
    onSectionToggle: (courseCode, sectionId, isSelected) {
      if (isSelected) {
        sections.removeWhere(
          (s) => s.courseCode == courseCode && s.sectionId == sectionId,
        );
      } else {
        sections.add(makeSelectedSection(
          courseCode: courseCode,
          sectionId: sectionId,
        ));
      }
      revision.value++;
    },
  );
  return (link: link, sections: sections, revision: revision);
}

void main() {
  group('ElectiveCourseList', () {
    testWidgets('without a link there is nothing to press', (tester) async {
      // Superseded the old "the Add buttons do nothing" expectation: a button
      // that renders live and silently no-ops is worse than no button. The
      // course list stays browsable; only the action is withheld.
      final courses = twoCourseNoClash();
      await pumpList(tester, courses: courses);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();

      expect(find.text('Add'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('with a link, Add writes through to the timetable', (tester) async {
      final courses = twoCourseNoClash();
      final l = makeLink(availableCourses: courses);
      await pumpList(tester, courses: courses, link: l.link);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(l.sections, hasLength(1));
      expect(l.sections.single.courseCode, 'CS F111');
      expect(l.sections.single.sectionId, 'L1');
    });

    testWidgets('the row flips to Remove once the section is on', (tester) async {
      final courses = twoCourseNoClash();
      final l = makeLink(availableCourses: courses);
      await pumpList(tester, courses: courses, link: l.link);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('Remove takes the section back off', (tester) async {
      final courses = twoCourseNoClash();
      final l = makeLink(availableCourses: courses);
      await pumpList(tester, courses: courses, link: l.link);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(l.sections, isEmpty);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('rebuilds on changes it did not make itself', (tester) async {
      // Stands in for accepting an exam-clash Override from a toast: the editor
      // mutates the selection and only bumps the revision.
      final courses = twoCourseNoClash();
      final l = makeLink(availableCourses: courses);
      await pumpList(tester, courses: courses, link: l.link);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();
      expect(find.text('Remove'), findsNothing);

      l.sections.add(makeSelectedSection(courseCode: 'CS F111', sectionId: 'L1'));
      l.revision.value++;
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('flags an exam clash against a course outside the elective list',
        (tester) async {
      // The whole point of the separate catalog: MATH F112 is on the timetable
      // but is not itself an elective, so it only exists in the catalog.
      final catalog = twoCourseNoClash();
      final elective = makeCourse(
        courseCode: 'BITS F225',
        courseTitle: 'Environmental Studies',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.S], hours: [8])],
        midSemExam: makeExam(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
      );

      final sections = [
        makeSelectedSection(
          courseCode: 'MATH F112',
          sectionId: 'L1',
          section: makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2]),
        ),
      ];
      final link = TimetableSelectionLink(
        selectedSections: sections,
        availableCourses: catalog,
        revision: ValueNotifier(0),
        timetableName: 'Sem 1',
        onSectionToggle: (_, __, ___) {},
      );

      await pumpList(
        tester,
        courses: [elective],
        catalog: [...catalog, elective],
        link: link,
      );

      // Wording is deliberately plain — "Midsem exam clashes with X", not
      // "MidSem clash". First-years read these before they know the jargon.
      expect(find.textContaining('Midsem exam clashes with MATH F112'),
          findsOneWidget);
    });

    testWidgets('misses that clash when no catalog is supplied', (tester) async {
      // Guards the default: with courses-as-catalog the selected CDC cannot be
      // resolved, so the warning is silently absent.
      final elective = makeCourse(
        courseCode: 'BITS F225',
        courseTitle: 'Environmental Studies',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.S], hours: [8])],
        midSemExam: makeExam(date: DateTime(2026, 3, 11), timeSlot: TimeSlot.MS2),
      );
      final link = TimetableSelectionLink(
        selectedSections: [
          makeSelectedSection(
            courseCode: 'MATH F112',
            sectionId: 'L1',
            section: makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2]),
          ),
        ],
        availableCourses: const [],
        revision: ValueNotifier(0),
        timetableName: 'Sem 1',
        onSectionToggle: (_, __, ___) {},
      );

      await pumpList(tester, courses: [elective], link: link);

      expect(find.textContaining('MidSem clash'), findsNothing);
    });
  });

  group('ElectiveTimetableBanner', () {
    testWidgets('names the timetable being edited', (tester) async {
      final l = makeLink();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ElectiveTimetableBanner(selectionLink: l.link)),
      ));

      expect(find.text('Adding to "Sem 1"'), findsOneWidget);
    });

    testWidgets('renders nothing without a link', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ElectiveTimetableBanner()),
      ));

      expect(find.byType(Row), findsNothing);
    });
  });

  group('read-only when no timetable is open', () {
    // The browsers are reachable two ways: from inside the editor (a timetable
    // is open, so Add writes to it) and from the timetable LIST (none is open).
    // In the second case the Add button used to render anyway, wired to a
    // no-op, so it looked live and silently did nothing.
    testWidgets('no Add button without a selection link', (tester) async {
      final course = makeCourse(courseCode: 'CS F211');
      await pumpList(tester, courses: [course]);
      // Sections are behind the course row, so expand it — otherwise the
      // absence below proves only that nothing was rendered yet.
      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();

      // The course and its sections are still browsable; only the action goes.
      expect(find.text('CS F211'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
    });

    testWidgets('the Add button is back once a timetable is open',
        (tester) async {
      final course = makeCourse(courseCode: 'CS F211');
      final l = makeLink(availableCourses: [course]);
      await pumpList(tester, courses: [course], link: l.link);
      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();

      // Control for the test above: same screen, timetable open, button there.
      expect(find.widgetWithText(TextButton, 'Add'), findsWidgets);
    });
  });

  group('the card distinguishes its two kinds of unavailable', () {
    // Previously a clash and "you already picked this component" rendered as
    // the same muted grey, so the card said "unavailable" without saying why.
    // They mean completely different things: one is a collision you cannot
    // resolve, the other is a choice you can simply change.

    testWidgets('a real clash names the course it collides with',
        (tester) async {
      // Two courses sharing Monday hour 1 — adding one blocks the other.
      final courses = [
        makeCourse(
          courseCode: 'CS F211',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])
          ],
        ),
        makeCourse(
          courseCode: 'MATH F211',
          sections: [
            makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1])
          ],
        ),
      ];
      final l = makeLink(availableCourses: courses);
      await pumpList(tester, courses: courses, link: l.link);

      await tester.tap(find.text(courses.first.courseCode));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Add').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text(courses[1].courseCode));
      await tester.pumpAndSettle();

      expect(find.textContaining('Clashes with'), findsWidgets);
    });

    testWidgets('a sibling of the chosen section offers to switch',
        (tester) async {
      // Two lectures for one course: taking one must not read as a clash, and
      // the other stays pressable — it replaces the one already taken.
      final course = makeCourse(
        courseCode: 'CS F211',
        sections: [
          makeSection(
              sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          makeSection(
              sectionId: 'L2', days: [DayOfWeek.T], hours: [4]),
        ],
      );
      final l = makeLink(availableCourses: [course]);
      await pumpList(tester, courses: [course], link: l.link);

      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Add').first);
      await tester.pumpAndSettle();

      expect(find.text('Replaces L1 on your timetable'), findsOneWidget);
      expect(find.textContaining('Clashes with'), findsNothing);

      final switchButton = find.widgetWithText(TextButton, 'Switch');
      expect(switchButton, findsOneWidget);
      expect(tester.widget<TextButton>(switchButton).onPressed, isNotNull);

      await tester.tap(switchButton);
      await tester.pumpAndSettle();
      // The stub link only adds; the editor's addSection is what drops L1. All
      // this asks is that the press reached it asking for L2.
      expect(l.sections.map((s) => s.sectionId), contains('L2'));
    });

    testWidgets('a lab over the course\'s own lecture is blocked, not offered',
        (tester) async {
      // The card used to check only *other* courses, so this row rendered a
      // live Add that the service then refused with a toast.
      final course = makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          makeSection(
              sectionId: 'P1',
              type: SectionType.P,
              days: [DayOfWeek.M],
              hours: [1]),
        ],
      );
      final l = makeLink(availableCourses: [course]);
      l.sections.add(makeSelectedSection(
          courseCode: 'CS F111',
          sectionId: 'L1',
          section: course.sections.first));
      await pumpList(tester, courses: [course], link: l.link);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Clashes with CS F111 L1'), findsOneWidget);
      final add = find.widgetWithText(TextButton, 'Add');
      expect(add, findsOneWidget);
      expect(tester.widget<TextButton>(add).onPressed, isNull);
    });

    testWidgets('a sibling that clashes elsewhere cannot be switched to',
        (tester) async {
      final course = makeCourse(
        courseCode: 'CS F211',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [2]),
        ],
      );
      final other = makeCourse(
        courseCode: 'MATH F112',
        sections: [makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2])],
      );
      final l = makeLink(availableCourses: [course, other]);
      l.sections.addAll([
        makeSelectedSection(
            courseCode: 'CS F211',
            sectionId: 'L1',
            section: course.sections.first),
        makeSelectedSection(
            courseCode: 'MATH F112',
            sectionId: 'L1',
            section: other.sections.first),
      ]);
      await pumpList(tester, courses: [course, other], link: l.link);

      await tester.tap(find.text('CS F211'));
      await tester.pumpAndSettle();

      // Labelled Switch, but the clash it would land on still blocks it.
      final switchButton = find.widgetWithText(TextButton, 'Switch');
      expect(switchButton, findsOneWidget);
      expect(tester.widget<TextButton>(switchButton).onPressed, isNull);
      expect(find.textContaining('Clashes with MATH F112'), findsOneWidget);
    });
  });
}
