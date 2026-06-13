import 'package:mocktail/mocktail.dart';
import 'package:timetable_maker/services/data/cgpa_service.dart';
import 'package:timetable_maker/services/core/course_catalog_service.dart';
import 'package:timetable_maker/services/core/timetable_service.dart';
import 'package:timetable_maker/services/data/course_data_service.dart';

class MockCGPAService extends Mock implements CGPAService {}

class MockCourseCatalogService extends Mock implements CourseCatalogService {}

class MockTimetableService extends Mock implements TimetableService {}

class MockCourseDataService extends Mock implements CourseDataService {}
