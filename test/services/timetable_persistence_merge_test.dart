import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/timetable_service.dart';
import 'package:timetable_maker/services/data/campus_service.dart';

Timetable timetable(String id, DateTime updatedAt) => Timetable(
  id: id,
  name: id,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: updatedAt,
  campus: Campus.hyderabad,
  availableCourses: const <Course>[],
  selectedSections: const [],
  clashWarnings: const [],
);

void main() {
  test('newer local fallback replaces stale cloud state', () {
    final cloud = timetable('same', DateTime(2026, 1, 1));
    final local = timetable('same', DateTime(2026, 1, 2));
    final merged = mergeTimetableCopies([cloud], [local]);

    expect(merged, hasLength(1));
    expect(identical(merged.single, local), isTrue);
    expect(newestTimetableCopy(cloud, local), same(local));
  });

  test('cloud state wins after it catches up to the pending copy', () {
    final cloud = timetable('same', DateTime(2026, 1, 3));
    final local = timetable('same', DateTime(2026, 1, 2));
    final merged = mergeTimetableCopies([cloud], [local]);

    expect(identical(merged.single, cloud), isTrue);
    expect(newestTimetableCopy(cloud, local), same(cloud));
  });

  test('merge retains unrelated cloud and local timetables', () {
    final cloud = timetable('cloud', DateTime(2026, 1, 1));
    final local = timetable('local', DateTime(2026, 1, 2));

    expect(mergeTimetableCopies([cloud], [local]).map((item) => item.id), [
      'cloud',
      'local',
    ]);
  });
}
