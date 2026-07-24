import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/exam_seating_screen.dart';

/// Combined exams are stored under one hyphen-joined code (a slash on the
/// seating sheet becomes a dash in the doc id). [examCoversCourse] must let a
/// student in either constituent course match the combined entry.
void main() {
  group('examCoversCourse', () {
    test('matches a plain single-course entry', () {
      expect(examCoversCourse('CS F211', 'CS F211'), isTrue);
    });

    test('ignores spaces and case', () {
      expect(examCoversCourse('cs f211', 'CSF211'), isTrue);
      expect(examCoversCourse('MATH F211', 'math  f211'), isTrue);
    });

    test('matches either side of a combined exam code', () {
      const combined = 'CS F211-MAC F242';
      expect(examCoversCourse(combined, 'CS F211'), isTrue);
      expect(examCoversCourse(combined, 'MAC F242'), isTrue);
    });

    test('matches the whole combined code verbatim too', () {
      expect(examCoversCourse('CS F211-MAC F242', 'CS F211-MAC F242'), isTrue);
    });

    test('does not match an unrelated course', () {
      expect(examCoversCourse('CS F211-MAC F242', 'BIO F110'), isFalse);
      expect(examCoversCourse('CS F211', 'CS F212'), isFalse);
    });

    test('does not match a partial/substring code', () {
      // 'CS F21' must not match 'CS F211' — only whole hyphen segments count.
      expect(examCoversCourse('CS F211', 'CS F21'), isFalse);
      expect(examCoversCourse('CS F211-MAC F242', 'F242'), isFalse);
    });

    test('empty target never matches', () {
      expect(examCoversCourse('CS F211', ''), isFalse);
      expect(examCoversCourse('CS F211', '   '), isFalse);
    });
  });

  group('displayExamCode', () {
    test('restores the slash on a combined code', () {
      expect(displayExamCode('CS F211-MAC F242'), 'CS F211 / MAC F242');
    });

    test('leaves a plain code untouched', () {
      expect(displayExamCode('CS F211'), 'CS F211');
    });
  });
}
