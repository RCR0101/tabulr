import '../models/normalized_timetable.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import '../services/incremental_timetable_service.dart';
import '../services/course_data_service.dart';
import 'timetable_repository.dart';

/// Implementation of TimetableRepository using hybrid storage
class HybridTimetableRepository implements TimetableRepository {
  final IncrementalTimetableService _timetableService;
  final CourseDataService _courseDataService;
  final String? _userId;

  HybridTimetableRepository({
    required IncrementalTimetableService timetableService,
    required CourseDataService courseDataService,
    String? userId,
  })  : _timetableService = timetableService,
        _courseDataService = courseDataService,
        _userId = userId;

  @override
  Future<void> saveTimetable(NormalizedTimetable timetable) async {
    await _timetableService.saveTimetable(timetable, _userId);
  }

  @override
  Future<NormalizedTimetable?> getTimetable(String timetableId) async {
    return await _timetableService.getTimetable(timetableId, _userId);
  }

  @override
  Future<List<NormalizedTimetable>> getAllTimetables() async {
    return await _timetableService.getAllTimetables(_userId);
  }

  @override
  Future<void> addSection(String timetableId, SectionReference section) async {
    await _timetableService.addSection(timetableId, section, _userId);
  }

  @override
  Future<void> removeSection(String timetableId, SectionReference section) async {
    await _timetableService.removeSection(timetableId, section, _userId);
  }

  @override
  Future<void> updateMetadata(String timetableId, Map<String, dynamic> updates) async {
    final updateBatch = TimetableUpdateBatch(
      timetableId: timetableId,
      metadataUpdates: updates,
    );
    await _timetableService.applyIncrementalUpdate(updateBatch, _userId);
  }

  @override
  Future<void> deleteTimetable(String timetableId) async {
    // Implementation depends on your deletion strategy
    // For now, we'll implement a simple approach
    throw UnimplementedError('Delete functionality not yet implemented');
  }

  @override
  Future<bool> needsCourseDataUpdate(String? currentVersion) async {
    return await _timetableService.needsCourseDataUpdate(currentVersion);
  }

  @override
  Future<Timetable> toLegacyTimetable(NormalizedTimetable normalized) async {
    return await _timetableService.toLegacyTimetable(normalized);
  }

  @override
  Future<NormalizedTimetable> migrateFromLegacy(Timetable legacy) async {
    return await _timetableService.migrateFromLegacy(legacy);
  }

  @override
  Stream<List<NormalizedTimetable>> watchTimetables() {
    // For now, return a simple stream
    // In a full implementation, you'd use Firestore streams
    return Stream.fromFuture(getAllTimetables());
  }
}

/// Implementation of CourseRepository
class HybridCourseRepository implements CourseRepository {
  final CourseDataService _courseDataService;

  HybridCourseRepository({
    required CourseDataService courseDataService,
  }) : _courseDataService = courseDataService;

  @override
  Future<List<Course>> getCourses() async {
    return await _courseDataService.fetchCourses();
  }

  @override
  Future<Course?> getCourse(String courseCode) async {
    final courses = await getCourses();
    try {
      return courses.firstWhere((course) => course.courseCode == courseCode);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> hasUpdates() async {
    // Implementation depends on your update detection strategy
    return false;
  }

  @override
  Future<String> getVersion() async {
    // Implementation depends on your versioning strategy
    return DateTime.now().toIso8601String();
  }

  @override
  Stream<List<Course>> watchCourses() {
    // For now, return a simple stream
    return Stream.fromFuture(getCourses());
  }
}

/// Factory for creating repositories
class RepositoryFactory {
  static TimetableRepository createTimetableRepository({String? userId}) {
    final timetableService = IncrementalTimetableService();
    final courseDataService = CourseDataService();
    
    return HybridTimetableRepository(
      timetableService: timetableService,
      courseDataService: courseDataService,
      userId: userId,
    );
  }

  static CourseRepository createCourseRepository() {
    final courseDataService = CourseDataService();
    
    return HybridCourseRepository(
      courseDataService: courseDataService,
    );
  }
}