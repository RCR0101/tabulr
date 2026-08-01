import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_trimmer.dart';

import '../helpers/test_data.dart';

/// A one-lecture course, so a shared hour is an unavoidable clash rather than
/// something the generator can route around by picking another section.
Course at(String code, DayOfWeek day, int hour) => makeCourse(
      courseCode: code,
      practicalCredits: 0,
      sections: [makeSection(sectionId: 'L1', days: [day], hours: [hour])],
    );

void main() {
  group('TimetableTrimmer', () {
    test('drops what cannot fit and keeps what can', () async {
      // Three courses all at Monday hour 1: at most one survives. The fourth is
      // elsewhere and must always come along.
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 1),
        at('CCC F111', DayOfWeek.M, 1),
        at('DDD F111', DayOfWeek.T, 3),
      ];
      final result = await TimetableTrimmer.trim(makeTimetable(courses: courses));

      expect(result.considered, hasLength(4));
      expect(result.options, isNotEmpty);
      for (final option in result.options) {
        final clashing =
            option.kept.where((c) => c != 'DDD F111').toList();
        expect(clashing.length, lessThanOrEqualTo(1),
            reason: 'three courses share one hour, so at most one is keepable');
        expect(option.kept, contains('DDD F111'),
            reason: 'it clashes with nothing and is free to keep');
        expect(option.kept.length + option.dropped.length, 4,
            reason: 'every course is accounted for as kept or dropped');
      }
    });

    test('offers genuinely different sets to choose between', () async {
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 1),
        at('CCC F111', DayOfWeek.M, 1),
      ];
      final result = await TimetableTrimmer.trim(makeTimetable(courses: courses));

      // The whole point of the feature: which one to give up is the student's
      // call, so more than one answer has to reach them.
      final sets = result.options.map((o) => o.kept.join('|')).toSet();
      expect(sets.length, greaterThan(1));
    });

    test('a pinned course survives every option', () async {
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 1),
        at('CCC F111', DayOfWeek.M, 1),
      ];
      final result = await TimetableTrimmer.trim(
        makeTimetable(courses: courses),
        pinned: {'BBB F111'},
      );

      expect(result.options, isNotEmpty);
      for (final option in result.options) {
        expect(option.kept, contains('BBB F111'));
        expect(option.kept, hasLength(1), reason: 'the other two clash with it');
      }
    });

    test('keepAtMost counts pinned courses toward the total', () async {
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.T, 2),
        at('CCC F111', DayOfWeek.W, 3),
        at('DDD F111', DayOfWeek.Th, 4),
      ];
      // Nothing clashes here, so only the cap can hold the count down.
      final result = await TimetableTrimmer.trim(
        makeTimetable(courses: courses),
        pinned: {'AAA F111'},
        keepAtMost: 2,
      );

      expect(result.options, isNotEmpty);
      for (final option in result.options) {
        expect(option.kept, contains('AAA F111'));
        expect(option.kept, hasLength(2),
            reason: 'two in total, not two on top of the pin');
      }
    });

    test('a required preference filters options out, and is named', () async {
      // Everything here runs on Monday, so requiring Monday free can never be
      // satisfied — the answer is which rule to relax, not "nothing fits".
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 3),
      ];
      final result = await TimetableTrimmer.trim(
        makeTimetable(courses: courses),
        preferences: TimetableConstraints(
          freeDayPreference: const [DayOfWeek.M],
          requireFreeDays: true,
        ),
      );

      expect(result.options, isEmpty);
      expect(result.unmetIntents, isNotEmpty,
          reason: 'the student set the rule, so the screen has to name it');
    });

    test('preferences reach the ranking rather than being dropped', () async {
      // Two keepable courses either side of a long gap, plus one that fills it.
      // Nothing clashes, so every course survives and the only thing the
      // preference can change is the order the options come back in.
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 2),
        at('CCC F111', DayOfWeek.M, 6),
      ];
      final tuned = await TimetableTrimmer.trim(
        makeTimetable(courses: courses),
        keepAtMost: 2,
        preferences: TimetableConstraints(minimizeGaps: true),
      );

      expect(tuned.options, isNotEmpty);
      // With gaps minimised the best two-course option is the adjacent pair,
      // not one spanning the empty middle of the day.
      expect(tuned.options.first.kept, containsAll(['AAA F111', 'BBB F111']),
          reason: 'minimizeGaps should favour the back-to-back pair');
    });

    test('two pinned courses that can never coexist are named', () async {
      final courses = [
        at('AAA F111', DayOfWeek.M, 1),
        at('BBB F111', DayOfWeek.M, 1),
      ];
      final result = await TimetableTrimmer.trim(
        makeTimetable(courses: courses),
        pinned: {'AAA F111', 'BBB F111'},
      );

      expect(result.options, isEmpty);
      expect(result.impossible, containsAll(['AAA F111', 'BBB F111']),
          reason: 'the answer is which pair is impossible, not "no results"');
    });
  });
}
