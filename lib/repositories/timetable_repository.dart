import '../models/normalized_timetable.dart';
import '../models/timetable.dart';
import '../models/course.dart';

/// Abstract interface for timetable data operations
abstract class TimetableRepository {
  /// Save a timetable
  Future<void> saveTimetable(NormalizedTimetable timetable);
  
  /// Get a timetable by ID
  Future<NormalizedTimetable?> getTimetable(String timetableId);
  
  /// Get all timetables for the current user
  Future<List<NormalizedTimetable>> getAllTimetables();
  
  /// Add a section to a timetable
  Future<void> addSection(String timetableId, SectionReference section);
  
  /// Remove a section from a timetable
  Future<void> removeSection(String timetableId, SectionReference section);
  
  /// Update timetable metadata
  Future<void> updateMetadata(String timetableId, Map<String, dynamic> updates);
  
  /// Delete a timetable
  Future<void> deleteTimetable(String timetableId);
  
  /// Check if course data needs updating
  Future<bool> needsCourseDataUpdate(String? currentVersion);
  
  /// Convert to legacy format for backward compatibility
  Future<Timetable> toLegacyTimetable(NormalizedTimetable normalized);
  
  /// Migrate from legacy format
  Future<NormalizedTimetable> migrateFromLegacy(Timetable legacy);
  
  /// Stream of timetable changes (for real-time updates)
  Stream<List<NormalizedTimetable>> watchTimetables();
}

/// Abstract interface for course data operations
abstract class CourseRepository {
  /// Get all available courses
  Future<List<Course>> getCourses();
  
  /// Get a specific course by code
  Future<Course?> getCourse(String courseCode);
  
  /// Check if course data has updates
  Future<bool> hasUpdates();
  
  /// Get course data version
  Future<String> getVersion();
  
  /// Stream of course data changes
  Stream<List<Course>> watchCourses();
}