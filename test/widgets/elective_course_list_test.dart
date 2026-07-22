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
    testWidgets('without a link the Add buttons do nothing', (tester) async {
      final courses = twoCourseNoClash();
      await pumpList(tester, courses: courses);

      await tester.tap(find.text('CS F111'));
      await tester.pumpAndSettle();

      final add = find.text('Add').first;
      expect(add, findsOneWidget);
      await tester.tap(add);
      await tester.pumpAndSettle();

      // Still offering Add — nothing was selected.
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

      expect(find.textContaining('MidSem clash with MATH F112'), findsOneWidget);
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
}
