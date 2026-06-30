import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/services/ui/export_service.dart';

/// Builds a minimal valid `.tt` payload. Callers can tweak the returned map
/// before encoding to exercise edge cases.
Map<String, dynamic> validTtMap({String campus = 'hyderabad'}) => {
      'version': '1.0',
      'timetable': {
        'name': 'My TT',
        'campus': campus,
        'courses': [
          {
            'courseCode': 'CS F111',
            'courseTitle': 'Computer Programming',
            'lectureCredits': 3.0,
            'practicalCredits': 1.0,
            'totalCredits': 4.0,
            'midSemExam': {
              'date': '2026-03-10T00:00:00.000',
              'timeSlot': 'MS1',
            },
            'endSemExam': {
              'date': '2026-05-10T00:00:00.000',
              'timeSlot': 'FN',
            },
          },
        ],
        'selectedSections': [
          {
            'courseCode': 'CS F111',
            'sectionId': 'L1',
            'section': {
              'sectionId': 'L1',
              'type': 'L',
              'instructor': 'Prof X',
              'room': 'F101',
              'schedule': [
                {
                  'days': ['M', 'W', 'F'],
                  'hours': [1],
                },
              ],
            },
          },
        ],
      },
    };

void main() {
  group('importFromTTContent', () {
    test('parses a valid .tt payload', () async {
      final tt = await ExportService.importFromTTContent(jsonEncode(validTtMap()));

      expect(tt.name, 'My TT');
      expect(tt.campus, Campus.hyderabad);
      expect(tt.availableCourses, hasLength(1));
      expect(tt.availableCourses.first.courseCode, 'CS F111');
      expect(tt.availableCourses.first.midSemExam?.timeSlot, TimeSlot.MS1);
      expect(tt.availableCourses.first.endSemExam?.timeSlot, TimeSlot.FN);
      expect(tt.selectedSections, hasLength(1));
      expect(tt.selectedSections.first.section.type, SectionType.L);
      expect(tt.selectedSections.first.section.schedule.first.days,
          containsAll([DayOfWeek.M, DayOfWeek.W, DayOfWeek.F]));
      // Imported timetables always get a freshly generated id.
      expect(tt.id, isNotEmpty);
      expect(tt.clashWarnings, isEmpty);
    });

    test('parses each campus value', () async {
      for (final entry in {
        'pilani': Campus.pilani,
        'hyderabad': Campus.hyderabad,
        'goa': Campus.goa,
      }.entries) {
        final tt = await ExportService.importFromTTContent(
            jsonEncode(validTtMap(campus: entry.key)));
        expect(tt.campus, entry.value);
      }
    });

    test('defaults to hyderabad for an unknown campus string', () async {
      final tt = await ExportService.importFromTTContent(
          jsonEncode(validTtMap(campus: 'atlantis')));
      expect(tt.campus, Campus.hyderabad);
    });

    test('defaults to hyderabad when campus is missing', () async {
      final map = validTtMap();
      (map['timetable'] as Map).remove('campus');
      final tt = await ExportService.importFromTTContent(jsonEncode(map));
      expect(tt.campus, Campus.hyderabad);
    });

    test('falls back to a default name when name is missing', () async {
      final map = validTtMap();
      (map['timetable'] as Map).remove('name');
      final tt = await ExportService.importFromTTContent(jsonEncode(map));
      expect(tt.name, 'Imported Timetable');
    });

    test('handles empty course and section lists', () async {
      final map = validTtMap();
      (map['timetable'] as Map)['courses'] = [];
      (map['timetable'] as Map)['selectedSections'] = [];
      final tt = await ExportService.importFromTTContent(jsonEncode(map));
      expect(tt.availableCourses, isEmpty);
      expect(tt.selectedSections, isEmpty);
    });

    test('throws on missing version', () async {
      final map = validTtMap()..remove('version');
      expect(() => ExportService.importFromTTContent(jsonEncode(map)),
          throwsA(isA<Exception>()));
    });

    test('throws on missing timetable', () async {
      final map = validTtMap()..remove('timetable');
      expect(() => ExportService.importFromTTContent(jsonEncode(map)),
          throwsA(isA<Exception>()));
    });

    test('throws on malformed JSON', () async {
      expect(() => ExportService.importFromTTContent('{not valid json'),
          throwsA(isA<Exception>()));
    });

    test('throws on an unknown section type', () async {
      final map = validTtMap();
      ((map['timetable'] as Map)['selectedSections'] as List).first['section']
          ['type'] = 'Z';
      expect(() => ExportService.importFromTTContent(jsonEncode(map)),
          throwsA(isA<Exception>()));
    });
  });
}
