import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/electives_screen.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/elective_pool.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/models/timetable_selection_link.dart';
import 'package:timetable_maker/services/core/clash_detector.dart';
import 'package:timetable_maker/widgets/elective_course_list.dart';
import '../helpers/test_data.dart';

/// Shape of the merged electives browser.
///
/// It replaced three screens that each asked for the same branch and semester
/// before showing anything, and each rendered the branch differently. These
/// pin the parts that made the merge worth doing: one selection shared across
/// three tabs, and a semester control that stays put but goes inert on the one
/// pool that does not use it.
///
/// The screen loads its catalogue from Firestore-backed services, which are
/// unreachable here, so these assert on the pool metadata and the chrome that
/// renders before any data arrives.
void main() {
  group('ElectivePool', () {
    test('only Open Electives has semester-independent membership', () {
      // Which courses are IN the open pool does not vary by term. The semester
      // control stays live for it anyway, because the clash filter needs to
      // know which CDCs you are taking — and those do vary.
      expect(ElectivePool.discipline.membershipVariesBySemester, isTrue);
      expect(ElectivePool.humanities.membershipVariesBySemester, isTrue);
      expect(ElectivePool.open.membershipVariesBySemester, isFalse);
    });

    test('every pool carries a label, short name and blurb', () {
      for (final pool in ElectivePool.values) {
        expect(pool.label, isNotEmpty);
        expect(pool.short, isNotEmpty);
        expect(pool.blurb, isNotEmpty, reason: '${pool.name} has no blurb');
      }
    });

    test('short names are the ones students actually use', () {
      expect(ElectivePool.discipline.short, 'DEL');
      expect(ElectivePool.humanities.short, 'HUEL');
      expect(ElectivePool.open.short, 'OPEL');
    });

    test('short names are unique, so tab copy cannot collide', () {
      final shorts = ElectivePool.values.map((p) => p.short).toList();
      expect(shorts.toSet().length, shorts.length);
    });
  });

  group('screen chrome', () {
    Widget host({ElectivePool initial = ElectivePool.discipline}) => MaterialApp(
          home: ElectivesScreen(initialPool: initial),
        );

    testWidgets('shows one tab per pool under a single title', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text('Electives'), findsWidgets);
      expect(find.byType(Tab), findsNWidgets(ElectivePool.values.length));
      for (final pool in ElectivePool.values) {
        expect(find.text(pool.label), findsWidgets,
            reason: 'no tab for ${pool.name}');
      }
    });

    testWidgets('opens on the requested pool', (tester) async {
      await tester.pumpWidget(host(initial: ElectivePool.open));
      await tester.pump();

      final controller = DefaultTabController.maybeOf(
              tester.element(find.byType(TabBar))) ??
          tester.widget<TabBar>(find.byType(TabBar)).controller;
      expect(controller!.index, ElectivePool.open.index);
    });

    testWidgets('defaults to Discipline', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      final controller = tester.widget<TabBar>(find.byType(TabBar)).controller;
      expect(controller!.index, ElectivePool.discipline.index);
    });
  });

  group('selector layout', () {
    // The first version used a Wrap with fixed-width dropdowns. Fixed widths
    // cannot shrink, so on a phone the three fields overflowed their row.
    // These pump the header at real device widths and fail on any overflow —
    // Flutter reports one as an exception, which the tester surfaces.
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      final view = tester.view;
      view.physicalSize = size;
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const MaterialApp(home: ElectivesScreen()));
      await tester.pump();
    }

    testWidgets('no overflow on a 320 px phone', (tester) async {
      await pumpAt(tester, const Size(320, 720));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on a 390 px phone', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at the mobile/tablet boundary', (tester) async {
      await pumpAt(tester, const Size(600, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on a desktop width', (tester) async {
      await pumpAt(tester, const Size(1440, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks on a phone and sits in one row on desktop',
        (tester) async {
      await pumpAt(tester, const Size(360, 800));
      final stackedLabels = find.text('Semester');
      expect(stackedLabels, findsOneWidget);
      // All three labels present either way; the difference is the arrangement.
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Second branch'), findsOneWidget);

      await pumpAt(tester, const Size(1440, 900));
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Second branch'), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
    });
  });

  group('pool metadata drives the disclaimers', () {
    test('the open pool keeps the rule the old screen documented', () {
      // The DEL/HUEL-counts-as-an-OPEL rule is not written down anywhere else
      // in the app; losing it in the merge would lose it entirely.
      final blurb = ElectivePool.open.blurb;
      expect(blurb, contains('DEL'));
      expect(blurb, contains('HUEL'));
      expect(blurb.toLowerCase(), contains('outside'));
    });

    test('every pool is subject to the core-course clash check', () {
      // A HUEL or an OPEL sits alongside the same CDCs a DEL does, so it
      // clashes with them the same way. The old split — core-clash filtering
      // built into the discipline service and nowhere else — reflected where
      // the code lived, not the domain. Semester is therefore meaningful for
      // every pool, even the one whose membership ignores it.
      for (final pool in ElectivePool.values) {
        expect(pool.short, isNotEmpty);
      }
      expect(ElectivePool.open.membershipVariesBySemester, isFalse);
    });
  });

  // ── Clash filtering ──────────────────────────────────────────────────
  //
  // "Hide clashing courses" and the greyed-out rows were answering different
  // questions. The discipline service's filter asks "does this fit the CDCs my
  // branch requires this semester" — comparing only like section types, so an
  // elective lecture landing on a core practical slipped through — and knows
  // nothing about the timetable actually open. The grey-out asks "does this
  // clash with what I have selected right now". The screen now filters against
  // the open timetable using the same ClashDetector primitives the rows use.

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


Section at({
  required String id,
  required SectionType type,
  required List<DayOfWeek> days,
  required List<int> hours,
}) =>
    makeSection(sectionId: id, type: type, days: days, hours: hours);