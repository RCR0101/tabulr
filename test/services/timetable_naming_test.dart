import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable_constraints.dart';
import 'package:timetable_maker/services/core/timetable_generator.dart';
import '../helpers/test_data.dart';

/// Names shown on the generated-timetable cards.
///
/// A name has one job: tell two options apart. The original implementation
/// derived it purely from week *shape* (free days, first/last hour, peak load),
/// so options that differ only in which section they picked — the common case,
/// since sections of a course usually sit in the same slots — all collapsed to
/// the same label and every one after the first fell back to "Option N".

Future<List<String>> _namesFor(
  List<Course> courses, {
  TimetableConstraints? constraints,
}) async {
  final generated = await TimetableGenerator.generateTimetables(
    courses,
    constraints ??
        TimetableConstraints(
          mandatoryCourses: courses.map((c) => c.courseCode).toList(),
        ),
    maxTimetables: 30,
  );
  return generated.map((t) => t.id).toList();
}

void main() {
  test('no two options share a name', () async {
    final names = await _namesFor(fiveCourseRealistic());

    expect(names, isNotEmpty);
    expect(names.toSet().length, names.length,
        reason: 'duplicate names in $names');
  });

  test('options that differ only by section are named by that section',
      () async {
    // Every section sits in the same slots, so all combinations have an
    // identical week shape. The section choice is the only real difference and
    // is what the name has to carry.
    final courses = [
      makeCourse(
        courseCode: 'CS F111',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
          makeSection(sectionId: 'L2', days: [DayOfWeek.M], hours: [1]),
        ],
      ),
      makeCourse(
        courseCode: 'MATH F112',
        sections: [
          makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [2]),
          makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [2]),
        ],
      ),
    ];

    final names = await _namesFor(courses);

    expect(names.length, greaterThan(1));
    expect(names.toSet().length, names.length,
        reason: 'duplicate names in $names');
    // The distinguishing fact, not a bare index.
    for (final name in names) {
      expect(name, contains('F11'),
          reason: '"$name" names no section, so it cannot be told apart');
    }
  });

  test('no name is a bare "Option N"', () async {
    // "Option 3" is unusable twice over: it says nothing about the timetable,
    // and its number was the pre-ranking index, so it did not even match the
    // position the card appeared in.
    final names = await _namesFor(fiveCourseRealistic());

    for (final name in names) {
      expect(RegExp(r'^Option \d+$').hasMatch(name), isFalse,
          reason: '"$name" is a bare index');
    }
  });

  test('a genuinely distinctive shape still gets a shape name', () async {
    // Naming by section is the fallback, not the default: when options really
    // do differ in shape, that is the more useful description.
    final courses = [
      makeCourse(
        courseCode: 'CS F111',
        sections: [
          // Mon/Wed/Fri mornings vs Tue/Thu afternoons — different weeks.
          makeSection(
              sectionId: 'L1',
              days: [DayOfWeek.M, DayOfWeek.W, DayOfWeek.F],
              hours: [1]),
          makeSection(
              sectionId: 'L2', days: [DayOfWeek.T, DayOfWeek.Th], hours: [7]),
        ],
      ),
    ];

    final names = await _namesFor(courses);

    expect(names.toSet().length, names.length);
    expect(names.any((n) => n.contains('day week') || n.contains('off')), isTrue,
        reason: 'expected a shape-based name in $names');
  });

  test('names are capitalised and non-empty', () async {
    final names = await _namesFor(fiveCourseRealistic());
    for (final name in names) {
      expect(name, isNotEmpty);
      expect(name[0], name[0].toUpperCase());
    }
  });
}
