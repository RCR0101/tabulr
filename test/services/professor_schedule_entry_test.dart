import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/professor_service.dart';

/// Field mapping for a professor's schedule rows.
///
/// Two writers disagree on spelling and both have to parse:
///   * rebuildProfessorSchedules (functions/admin.js) writes snake_case
///     (`course_code`, `section_id`) straight into Firestore;
///   * ProfessorScheduleEntry.toJson writes camelCase, and backs the local
///     cache.
///
/// Reading only camelCase left courseCode and sectionId empty for everything
/// that came from Firestore. Nothing threw — the chips in a professor's
/// schedule dialog just rendered a blank label, and `addable` (which matches
/// the entry's course code against the open timetable's catalogue) could never
/// match, so tap-to-add silently did nothing.
void main() {
  group('ProfessorScheduleEntry.fromJson', () {
    test('reads the snake_case shape Firestore holds', () {
      final e = ProfessorScheduleEntry.fromJson(const {
        'course_code': 'CS F111',
        'section_id': 'L1',
        'room': 'F102',
        'days': ['DayOfWeek.M', 'DayOfWeek.W'],
        'hours': [1, 2],
      });

      expect(e.courseCode, 'CS F111');
      expect(e.sectionId, 'L1');
      expect(e.room, 'F102');
      expect(e.days, ['DayOfWeek.M', 'DayOfWeek.W']);
      expect(e.hours, [1, 2]);
    });

    test('reads the camelCase shape the local cache holds', () {
      final e = ProfessorScheduleEntry.fromJson(const {
        'courseCode': 'MATH F112',
        'sectionId': 'T3',
        'room': 'D201',
        'days': ['DayOfWeek.F'],
        'hours': [5],
      });

      expect(e.courseCode, 'MATH F112');
      expect(e.sectionId, 'T3');
    });

    test('round-trips through toJson', () {
      const source = {
        'course_code': 'PHY F111',
        'section_id': 'P2',
        'room': 'LAB1',
        'days': ['DayOfWeek.T'],
        'hours': [7, 8],
      };
      final once = ProfessorScheduleEntry.fromJson(source);
      final twice = ProfessorScheduleEntry.fromJson(once.toJson());

      expect(twice.courseCode, 'PHY F111');
      expect(twice.sectionId, 'P2');
      expect(twice.hours, [7, 8]);
    });

    test('a missing code is empty rather than throwing', () {
      final e = ProfessorScheduleEntry.fromJson(const {'room': 'X'});
      expect(e.courseCode, '');
      expect(e.sectionId, '');
    });
  });
}
