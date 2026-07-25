import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_selection_link.dart';
import 'package:timetable_maker/services/core/clash_detector.dart';
import 'package:timetable_maker/widgets/elective_course_list.dart';

import '../helpers/test_data.dart';

/// Agreement between "hide clashing courses" and the greyed-out rows.
///
/// These were answering different questions. The discipline service's filter
/// asks "does this fit the CDCs my branch requires this semester" — comparing
/// only like section types, so an elective lecture landing on a core practical
/// slipped through — and knows nothing about the timetable actually open. The
/// grey-out asks "does this clash with what I have selected right now". A
/// course could pass the first and still show every row greyed by the second.
///
/// The screen now also filters against the open timetable, using the same
/// ClashDetector primitives the rows use. These tests pin the primitives and
/// the rendering; the screen-level wiring is covered in electives_screen_test.

Section at({
  required String id,
  required SectionType type,
  required List<DayOfWeek> days,
  required List<int> hours,
}) =>
    makeSection(sectionId: id, type: type, days: days, hours: hours);

void main() {
  group('the clash primitives the filter and the rows share', () {
    test('sectionsConflict is type-agnostic', () {
      // The core-course filter compares lectures only against lectures, so this
      // case — an elective lecture on top of a core practical — was invisible
      // to it while the rows greyed it out.
      final lecture =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]);
      final practical =
          at(id: 'P1', type: SectionType.P, days: [DayOfWeek.M], hours: [3]);

      expect(ClashDetector.sectionsConflict(lecture, practical), isTrue);
    });

    test('a different hour on the same day is not a clash', () {
      final a =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]);
      final b =
          at(id: 'L2', type: SectionType.L, days: [DayOfWeek.M], hours: [4]);

      expect(ClashDetector.sectionsConflict(a, b), isFalse);
    });

    test('the same hour on a different day is not a clash', () {
      final a =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]);
      final b =
          at(id: 'L2', type: SectionType.L, days: [DayOfWeek.T], hours: [3]);

      expect(ClashDetector.sectionsConflict(a, b), isFalse);
    });

    test('exams collide only on the same date and slot', () {
      final may10FN = makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.FN);
      final may10AN = makeExam(date: DateTime(2026, 5, 10), timeSlot: TimeSlot.AN);
      final may11FN = makeExam(date: DateTime(2026, 5, 11), timeSlot: TimeSlot.FN);

      expect(ClashDetector.examDatesConflict(may10FN, may10FN), isTrue);
      expect(ClashDetector.examDatesConflict(may10FN, may10AN), isFalse);
      expect(ClashDetector.examDatesConflict(may10FN, may11FN), isFalse);
    });
  });

  group('rows still show the clash when a course survives the filter', () {
    /// A course keeps a free section, so it is takeable — but one of its
    /// sections lands on the selection and must read as blocked.
    testWidgets('a clashing section greys while its sibling stays addable',
        (tester) async {
      final elective = makeCourse(
        courseCode: 'CS F320',
        sections: [
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]),
          at(id: 'L2', type: SectionType.L, days: [DayOfWeek.T], hours: [5]),
        ],
      );
      final core = makeCourse(
        courseCode: 'MATH F211',
        sections: [
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]),
        ],
      );

      final selected = [
        SelectedSection(
          courseCode: core.courseCode,
          sectionId: 'L1',
          section: core.sections.first,
        ),
      ];
      final link = TimetableSelectionLink(
        selectedSections: selected,
        availableCourses: [elective, core],
        revision: ValueNotifier(0),
        timetableName: 'Sem 1',
        onSectionToggle: (_, __, ___) {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElectiveCourseList(
            courses: [elective],
            catalog: [elective, core],
            selectionLink: link,
          ),
        ),
      ));
      await tester.tap(find.text('CS F320'));
      await tester.pumpAndSettle();

      // L1 collides with the selected MATH F211 L1 and says so; L2 does not.
      expect(find.textContaining('Clashes with MATH F211'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Add'), findsWidgets);
    });
  });

  group('core-course clashes are not a discipline-only concern', () {
    // The original split filtered DELs against the CDCs and left HUELs and
    // OPELs unchecked — not because those pools cannot clash with core
    // courses (they obviously can; they are taken in the same week) but
    // because getFilteredDisciplineElectivesWithClashDetection happened to
    // live in the discipline service. getCoreCourseCodes is on
    // BranchStructureService and is branch+semester in, CDC codes out, with
    // nothing pool-specific about it.

    test('a core lecture blocks any elective sharing its slot', () {
      final coreLecture =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [2]);

      // Whatever pool the elective came from, the collision is identical.
      final huelSection =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [2]);
      final opelSection =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [2]);

      expect(ClashDetector.sectionsConflict(huelSection, coreLecture), isTrue);
      expect(ClashDetector.sectionsConflict(opelSection, coreLecture), isTrue);
    });

    test('a core practical blocks an elective lecture', () {
      // The case the like-for-like service filter could never see.
      final corePractical =
          at(id: 'P1', type: SectionType.P, days: [DayOfWeek.W], hours: [6, 7]);
      final electiveLecture =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.W], hours: [7]);

      expect(
          ClashDetector.sectionsConflict(electiveLecture, corePractical), isTrue);
    });

    test('a core exam blocks an elective sharing its date and slot', () {
      final core = makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1);
      final elective =
          makeExam(date: DateTime(2026, 3, 10), timeSlot: TimeSlot.MS1);

      expect(ClashDetector.examDatesConflict(elective, core), isTrue);
    });
  });

  group('a CDC section is chosen, not fixed', () {
    // The distinction that makes "clash with a CDC" mean something specific.
    //
    // A section already on the timetable is FIXED — the student picked it, so
    // any collision with it is real. A CDC's section is NOT yet picked: the
    // student must take the course, but chooses among its sections. Colliding
    // with one lecture of a course offering three is not a clash; they take
    // one of the other two.
    //
    // Flattening every CDC section into a hard blocker over-blocks, hiding
    // electives that are perfectly takeable. These pin the rule the filter
    // applies: a CDC component blocks only when EVERY one of its sections
    // collides.

    /// Mirrors _dropClashes: blocked only if every section of the component
    /// collides with the candidate.
    bool componentBlocks(List<Section> component, Section candidate) =>
        component.every((s) => ClashDetector.sectionsConflict(candidate, s));

    test('one colliding CDC lecture out of two does not block', () {
      final cdcLectures = [
        at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]),
        at(id: 'L2', type: SectionType.L, days: [DayOfWeek.T], hours: [5]),
      ];
      final elective =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]);

      // Collides with L1 but not L2 — the student takes L2.
      expect(ClashDetector.sectionsConflict(elective, cdcLectures.first), isTrue);
      expect(componentBlocks(cdcLectures, elective), isFalse);
    });

    test('every CDC lecture colliding does block', () {
      final cdcLectures = [
        at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]),
        at(id: 'L2', type: SectionType.L, days: [DayOfWeek.M], hours: [3]),
      ];
      final elective =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [3]);

      expect(componentBlocks(cdcLectures, elective), isTrue);
    });

    test('a single-section CDC component blocks on one collision', () {
      // The common case: one lecture, no alternative to move to.
      final cdcLectures = [
        at(id: 'L1', type: SectionType.L, days: [DayOfWeek.W], hours: [2]),
      ];
      final elective =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.W], hours: [2]);

      expect(componentBlocks(cdcLectures, elective), isTrue);
    });

    test('components are judged separately', () {
      // Free against the lectures, trapped by the single practical: still
      // blocked, because the student must take that practical.
      final lectures = [
        at(id: 'L1', type: SectionType.L, days: [DayOfWeek.M], hours: [1]),
        at(id: 'L2', type: SectionType.L, days: [DayOfWeek.T], hours: [1]),
      ];
      final practicals = [
        at(id: 'P1', type: SectionType.P, days: [DayOfWeek.F], hours: [8, 9]),
      ];
      final elective =
          at(id: 'L1', type: SectionType.L, days: [DayOfWeek.F], hours: [8]);

      expect(componentBlocks(lectures, elective), isFalse);
      expect(componentBlocks(practicals, elective), isTrue);
    });
  });
}
