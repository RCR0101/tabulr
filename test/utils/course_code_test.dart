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

  group('Firestore document ids', () {
    test('round-trips a code through its document id', () {
      expect(courseCodeToDocId('CS F211'), 'CS_F211');
      expect(docIdToCourseCode('CS_F211'), 'CS F211');
      expect(docIdToCourseCode(courseCodeToDocId('MATH F112')), 'MATH F112');
    });

    test('leaves a code with no space alone', () {
      expect(courseCodeToDocId('BITS'), 'BITS');
      expect(docIdToCourseCode('BITS'), 'BITS');
    });

    test('is distinct from normalizeCourseCode', () {
      // normalizeCourseCode strips whitespace for cross-source comparison and
      // must never be used to build a document id.
      expect(normalizeCourseCode('CS F211'), 'CSF211');
      expect(courseCodeToDocId('CS F211'), 'CS_F211');
    });
  });
}
