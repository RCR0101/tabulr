import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/export_options.dart';

void main() {
  group('ExportOptions', () {
    test('defaults all fields to true', () {
      const options = ExportOptions();
      expect(options.showCourseCode, isTrue);
      expect(options.showCourseTitle, isTrue);
      expect(options.showSectionId, isTrue);
      expect(options.showInstructor, isTrue);
      expect(options.showRoom, isTrue);
      expect(options.showTimeSlots, isTrue);
      expect(options.showExamDates, isTrue);
    });

    test('copyWith overrides single field', () {
      const original = ExportOptions();
      final copied = original.copyWith(showRoom: false);

      expect(copied.showRoom, isFalse);
      expect(copied.showCourseCode, isTrue);
      expect(copied.showInstructor, isTrue);
    });

    test('copyWith overrides multiple fields', () {
      const original = ExportOptions();
      final copied = original.copyWith(
        showCourseCode: false,
        showInstructor: false,
        showExamDates: false,
      );

      expect(copied.showCourseCode, isFalse);
      expect(copied.showInstructor, isFalse);
      expect(copied.showExamDates, isFalse);
      expect(copied.showCourseTitle, isTrue);
      expect(copied.showSectionId, isTrue);
    });

    test('copyWith with no args returns equivalent object', () {
      const original = ExportOptions(showRoom: false);
      final copied = original.copyWith();

      expect(copied.showRoom, isFalse);
      expect(copied.showCourseCode, isTrue);
    });
  });
}
