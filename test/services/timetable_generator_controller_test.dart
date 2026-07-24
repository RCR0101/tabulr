import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/services/core/timetable_generator_controller.dart';
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
    ctrl.freeDayPreference.add(DayOfWeek.F);

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
}
