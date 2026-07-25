import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/utils/course_utils.dart';
import '../helpers/test_data.dart';

/// Courses with no sections are hidden by default.
///
/// They cannot be added to a timetable, so they are noise in a list whose
/// purpose is picking a section. They exist because the booklet prints each
/// course in both semester tables and the copy for the term it is not offered
/// in carries no rows — the same source as the duplicate rows dedupe_by_doc_id
/// collapses on upload.
void main() {
  final running = makeCourse(courseCode: 'CS F211');
  final notRunning = Course(
    courseCode: 'CS F999',
    courseTitle: 'Not Offered This Sem',
    lectureCredits: 3,
    practicalCredits: 0,
    totalCredits: 3,
    sections: const [],
  );

  test('drops a course with no sections', () {
    final result = CourseUtils.filterOutSectionless([running, notRunning]);
    expect(result.map((c) => c.courseCode), ['CS F211']);
  });

  test('keeps every course that has at least one section', () {
    final result = CourseUtils.filterOutSectionless([running]);
    expect(result, hasLength(1));
  });

  test('an empty list stays empty rather than throwing', () {
    expect(CourseUtils.filterOutSectionless(const []), isEmpty);
  });

  test('does not mutate its input', () {
    final input = [running, notRunning];
    CourseUtils.filterOutSectionless(input);
    expect(input, hasLength(2));
  });
}
