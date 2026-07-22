import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/utils/course_code.dart';

void main() {
  group('normalizeCourseCode', () {
    test('collapses the spacing that differs between sources', () {
      expect(normalizeCourseCode('CS F320'), 'CSF320');
      expect(normalizeCourseCode('CSF320'), 'CSF320');
      expect(normalizeCourseCode('CS  F320'), 'CSF320');
      expect(normalizeCourseCode(' cs f320 '), 'CSF320');
    });

    test('is the same function AcademicRecord matches with', () {
      // Two normalizers that drift apart would break minor progress silently,
      // so the model delegates here rather than keeping its own copy.
      expect(AcademicRecord.normalizeCode('CS F320'),
          normalizeCourseCode('CS F320'));
    });

    test('leaves an already-canonical code alone', () {
      expect(normalizeCourseCode('BITSF225'), 'BITSF225');
    });

    test('handles an empty code without throwing', () {
      expect(normalizeCourseCode(''), '');
    });
  });
}
