import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/minor_programme.dart';

void main() {
  MinorProgramme minor({
    String name = 'Data Science',
    List<MinorCourseGroup>? groups,
    List<String> campuses = const [],
  }) =>
      MinorProgramme(
        id: 'data-science',
        name: name,
        description: 'Learn the basic skills required by a data scientist.',
        minCourses: 5,
        minUnits: 15,
        campuses: campuses,
        groups: groups ??
            [
              const MinorCourseGroup(name: 'Core Courses', courses: [
                MinorCourse(
                    code: 'CS F320',
                    title: 'Foundations of Data Science',
                    units: 3),
                MinorCourse(
                    code: 'BITS F464', title: 'Machine Learning', units: 3),
              ]),
              const MinorCourseGroup(name: 'Electives', courses: [
                MinorCourse(code: 'CS F425', title: 'Deep Learning', units: 3),
              ]),
            ],
      );

  group('courseCount', () {
    test('sums courses across every group', () {
      expect(minor().courseCount, 3);
    });

    test('is zero when there are no groups', () {
      expect(minor(groups: const []).courseCount, 0);
    });
  });

  group('search', () {
    test('an empty query matches', () {
      expect(minor().matches(''), isTrue);
    });

    test('matches on the minor name, case-insensitively', () {
      expect(minor().matches('data science'), isTrue);
      expect(minor().matches('DATA'), isTrue);
    });

    test('matches on a course code — "which minors use this course?"', () {
      expect(minor().matches('CS F320'), isTrue);
      expect(minor().matches('cs f425'), isTrue);
    });

    test('matches on a course title', () {
      expect(minor().matches('Machine Learning'), isTrue);
    });

    test('does not match unrelated text', () {
      expect(minor().matches('aerodynamics'), isFalse);
    });
  });

  group('campus availability', () {
    test('an empty campus list means available everywhere', () {
      expect(minor().offeredAt('hyderabad'), isTrue);
      expect(minor().offeredAt(null), isTrue);
    });

    test('a populated list restricts to those campuses', () {
      final m = minor(campuses: const ['hyderabad']);
      expect(m.offeredAt('hyderabad'), isTrue);
      expect(m.offeredAt('pilani'), isFalse);
    });

    test('an unknown campus still shows restricted minors rather than hiding them', () {
      expect(minor(campuses: const ['pilani']).offeredAt(null), isTrue);
    });
  });

  group('serialisation', () {
    test('toMap round-trips through fromMap for groups and courses', () {
      final map = minor().toMap();
      final groups = (map['groups'] as List)
          .map((g) => MinorCourseGroup.fromMap(Map<String, dynamic>.from(g)))
          .toList();

      expect(groups.length, 2);
      expect(groups.first.name, 'Core Courses');
      expect(groups.first.courses.first.code, 'CS F320');
      expect(groups.first.courses.first.units, 3);
    });

    test('omits null units rather than writing a null field', () {
      const c = MinorCourse(code: 'BIO F266', title: 'Study Project');
      expect(c.toMap().containsKey('units'), isFalse);
      expect(MinorCourse.fromMap(c.toMap()).units, isNull);
    });

    test('tolerates missing fields from Firestore', () {
      final g = MinorCourseGroup.fromMap(const {});
      expect(g.name, '');
      expect(g.courses, isEmpty);
    });
  });

  group('copyWith', () {
    test('keeps the id and updates only what is passed', () {
      final updated = minor().copyWith(name: 'Renamed', needsReview: true);
      expect(updated.id, 'data-science');
      expect(updated.name, 'Renamed');
      expect(updated.needsReview, isTrue);
      expect(updated.minUnits, 15);
    });
  });
}
