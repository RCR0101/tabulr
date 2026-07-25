import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_generator_controller.dart';
import 'package:timetable_maker/services/core/timetable_ranker.dart';
import '../helpers/test_data.dart';

/// The controller is the seam the UI actually calls: generate() must run the
/// generator and hand back a ranked, tier-ordered result.
void main() {
  test('generate() ranks candidates and exposes them tier-ordered', () async {
    final courses = fiveCourseRealistic();
    final ctrl = TimetableGeneratorController();
    ctrl.reset();
    for (final c in courses) {
      ctrl.addMandatoryCourse(c.courseCode);
    }
    ctrl.toggleFreeDayPreference(DayOfWeek.F);

    final result = await ctrl.generate(courses);

    expect(result.ranked, isNotEmpty);
    expect(ctrl.rankingResult, isNotNull);
    expect(ctrl.rankedTimetables.length, result.ranked.length);
    // Top option is always a best trade-off, and tiers never decrease.
    expect(ctrl.rankedTimetables.first.tier, 1);
    for (var i = 1; i < ctrl.rankedTimetables.length; i++) {
      expect(ctrl.rankedTimetables[i].tier, greaterThanOrEqualTo(ctrl.rankedTimetables[i - 1].tier));
    }
    expect(ctrl.isGenerating, isFalse);
  });

  test('an infeasible hard constraint returns empty + a conflict diagnosis', () async {
    final courses = fiveCourseRealistic();
    final ctrl = TimetableGeneratorController();
    ctrl.reset();
    for (final c in courses) {
      ctrl.addMandatoryCourse(c.courseCode);
    }
    // Require every class at 6 PM or later — impossible for this catalogue.
    ctrl.earliestStartSlot = 11;
    ctrl.requireHoursWindow = true;

    final result = await ctrl.generate(courses);

    expect(result.ranked, isEmpty);
    expect(result.unmetIntents, isNotEmpty);
    expect(result.unmetIntents.first, contains('class-hours window'));
  });

  group('notifications', () {
    late TimetableGeneratorController ctrl;
    late int notifications;

    setUp(() {
      ctrl = TimetableGeneratorController();
      notifications = 0;
      ctrl.addListener(() => notifications++);
    });

    test('every mutator notifies', () {
      ctrl.addMandatoryCourse('CS F111');
      expect(notifications, 1);

      ctrl.maxHoursPerDay = 6;
      expect(notifications, 2);

      // Refine chips used to write these fields directly and notify nothing;
      // they only appeared to work because generate() notified afterwards.
      ctrl.setAxisImportance(RankAxis.freeDays, AxisImportance.high);
      expect(notifications, 3);

      ctrl.earliestStartSlot = 2;
      expect(notifications, 4);

      ctrl.minimizeGaps = true;
      expect(notifications, 5);
    });

    test('setting a field to its current value does not notify', () {
      ctrl.maxHoursPerDay = 8; // already the default
      ctrl.minimizeGaps = false;
      ctrl.timeOfDayPreference = TimeOfDayPreference.none;
      expect(notifications, 0);
    });

    test('a no-op removal does not notify', () {
      ctrl.removeOptionalCourse('NOT THERE');
      ctrl.removeMandatoryCourse('NOT THERE');
      expect(notifications, 0);
    });

    test('adding a duplicate course does not notify', () {
      ctrl.addMandatoryCourse('CS F111');
      expect(notifications, 1);
      ctrl.addMandatoryCourse('CS F111');
      expect(notifications, 1);
    });
  });

  group('course list invariants', () {
    test('collections are unmodifiable so the UI cannot bypass notify', () {
      final ctrl = TimetableGeneratorController();
      expect(() => ctrl.mandatoryCourses.add('X'), throwsUnsupportedError);
      expect(() => ctrl.optionalCourses.add('X'), throwsUnsupportedError);
      expect(() => ctrl.freeDayPreference.add(DayOfWeek.M), throwsUnsupportedError);
      expect(() => ctrl.axisImportance[RankAxis.freeDays] = AxisImportance.high,
          throwsUnsupportedError);
    });

    test('a course cannot be mandatory and optional at once', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addOptionalCourse('CS F111');
      ctrl.addMandatoryCourse('CS F111');

      expect(ctrl.mandatoryCourses, ['CS F111']);
      expect(ctrl.optionalCourses, isEmpty);

      // And the other direction is refused rather than duplicating.
      ctrl.addOptionalCourse('CS F111');
      expect(ctrl.optionalCourses, isEmpty);
    });

    test('addMandatoryCourses does not notify when nothing moves', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addMandatoryCourse('CS F111');
      var notifications = 0;
      ctrl.addListener(() => notifications++);

      ctrl.addMandatoryCourses(['CS F111']);

      expect(notifications, 0);
    });

    test('addMandatoryCourses promotes optionals and counts only new ones', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addOptionalCourse('CS F111');
      ctrl.addMandatoryCourse('MATH F111');

      final added = ctrl.addMandatoryCourses(['CS F111', 'MATH F111', 'PHY F111']);

      expect(added, 2); // MATH F111 was already mandatory
      expect(ctrl.optionalCourses, isEmpty);
      expect(ctrl.mandatoryCourses, ['MATH F111', 'CS F111', 'PHY F111']);
    });

    test('moveOptionalCourse reorders by code, not by cluster index', () {
      final ctrl = TimetableGeneratorController();
      for (final c in ['A', 'B', 'C', 'D']) {
        ctrl.addOptionalCourse(c);
      }

      ctrl.moveOptionalCourse('D', beforeCode: 'B');
      expect(ctrl.optionalCourses, ['A', 'D', 'B', 'C']);
    });

    test('optionalTarget clamps when optionals are removed', () {
      final ctrl = TimetableGeneratorController();
      for (final c in ['A', 'B', 'C']) {
        ctrl.addOptionalCourse(c);
      }
      ctrl.optionalTarget = 3;
      expect(ctrl.optionalTarget, 3);

      ctrl.removeOptionalCourse('C');
      // Reading clamps rather than the widget fixing it up mid-build.
      expect(ctrl.optionalTarget, 2);

      ctrl.removeOptionalCourse('B');
      ctrl.removeOptionalCourse('A');
      expect(ctrl.optionalTarget, isNull);
    });
  });

  group('dependent constraints', () {
    test('clearing lunch protection drops its require flag', () {
      final ctrl = TimetableGeneratorController();
      ctrl.protectLunchBreak = true;
      ctrl.requireLunchFree = true;

      ctrl.protectLunchBreak = false;

      expect(ctrl.requireLunchFree, isFalse);
    });

    test('widening the hours window to full range drops its require flag', () {
      final ctrl = TimetableGeneratorController();
      ctrl.setHoursWindow(startSlot: 3, endSlot: 9);
      ctrl.requireHoursWindow = true;
      expect(ctrl.hasHoursWindow, isTrue);

      ctrl.setHoursWindow(startSlot: 1, endSlot: 12);

      expect(ctrl.hasHoursWindow, isFalse);
      expect(ctrl.requireHoursWindow, isFalse);
    });

    test('clearing the last free day drops its require flag', () {
      final ctrl = TimetableGeneratorController();
      ctrl.toggleFreeDayPreference(DayOfWeek.F);
      ctrl.requireFreeDays = true;

      ctrl.toggleFreeDayPreference(DayOfWeek.F);

      expect(ctrl.freeDayPreference, isEmpty);
      expect(ctrl.requireFreeDays, isFalse);
    });
  });

  group('avoidance merging', () {
    test('two entries for one day merge into a single sorted entry', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addTimeAvoidance(TimeAvoidance(day: DayOfWeek.M, hours: [3, 1]));
      ctrl.addTimeAvoidance(TimeAvoidance(day: DayOfWeek.M, hours: [2, 3]));

      expect(ctrl.avoidTimes.length, 1);
      expect(ctrl.avoidTimes.single.hours, [1, 2, 3]);
    });

    test('different days stay separate', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addLabAvoidance(LabAvoidance(day: DayOfWeek.M, hours: [1]));
      ctrl.addLabAvoidance(LabAvoidance(day: DayOfWeek.T, hours: [1]));

      expect(ctrl.avoidLabs.length, 2);
    });

    test('setInstructorRankings({}) clears, and does not throw', () {
      // The UI had a "clear all rankings" button calling
      // instructorRankings.clear() on what is now an unmodifiable view — it
      // would have thrown at runtime. It goes through the setter instead.
      final ctrl = TimetableGeneratorController();
      ctrl.setInstructorRankings({
        'CS F111': InstructorRankings(lectureInstructors: const ['Prof A']),
      });
      expect(ctrl.instructorRankings, isNotEmpty);

      ctrl.setInstructorRankings(const {});

      expect(ctrl.instructorRankings, isEmpty);
    });

    test('avoided instructors are deduplicated', () {
      final ctrl = TimetableGeneratorController();
      ctrl.addAvoidedInstructors(['Prof A', 'Prof B']);
      ctrl.addAvoidedInstructors(['Prof B', 'Prof C']);

      expect(ctrl.avoidedInstructors, ['Prof A', 'Prof B', 'Prof C']);
    });
  });
}
