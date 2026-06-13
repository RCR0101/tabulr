import 'package:mocktail/mocktail.dart';
import 'package:timetable_maker/models/all_course.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/services/data/cgpa_service.dart';
import 'package:timetable_maker/services/core/course_catalog_service.dart';
import 'package:timetable_maker/services/core/cgpa_calculator_controller.dart';
import 'mock_services.dart';

void registerFallbackValues() {
  registerFallbackValue(SemesterData(semesterName: ''));
  registerFallbackValue(<String, SemesterData>{});
  registerFallbackValue(<AllCourse>[]);
}

CGPACalculatorController createTestController({
  CGPAService? cgpaService,
  CourseCatalogService? coursesService,
}) {
  final mockCgpa = cgpaService ?? _defaultMockCGPAService();
  final mockCourses = coursesService ?? _defaultMockCourseCatalogService();
  return CGPACalculatorController(
    cgpaService: mockCgpa,
    coursesService: mockCourses,
  );
}

MockCGPAService _defaultMockCGPAService() {
  final mock = MockCGPAService();
  when(() => mock.loadAllCGPAData()).thenAnswer((_) async => CGPAData());
  when(() => mock.saveSemesterData(any(), any())).thenAnswer((_) async => true);
  when(() => mock.saveAllSemesters(any())).thenAnswer((_) async => true);
  when(() => mock.loadSemesterData(any())).thenAnswer((_) async => null);
  when(() => mock.deleteSemesterData(any())).thenAnswer((_) async => true);
  when(() => mock.deleteAllCGPAData()).thenAnswer((_) async => true);
  when(() => mock.prefetch()).thenAnswer((_) async {});
  when(() => mock.invalidateCache()).thenReturn(null);
  return mock;
}

MockCourseCatalogService _defaultMockCourseCatalogService() {
  final mock = MockCourseCatalogService();
  when(() => mock.fetchAllCourses(
    forceRefresh: any(named: 'forceRefresh'),
    campus: any(named: 'campus'),
  )).thenAnswer((_) async => []);
  when(() => mock.searchCourses(any(), any())).thenReturn([]);
  when(() => mock.getCourseTitle(any(), campus: any(named: 'campus')))
      .thenAnswer((_) async => '');
  when(() => mock.getCourseTitles(any(), campus: any(named: 'campus')))
      .thenAnswer((_) async => {});
  when(() => mock.getCachedCourseTitle(any(), campus: any(named: 'campus')))
      .thenReturn(null);
  when(() => mock.clearCache()).thenReturn(null);
  return mock;
}
