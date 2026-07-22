import '../../models/academic_record.dart';
import '../../models/cgpa_data.dart';
import '../ui/secure_logger.dart';
import 'cgpa_service.dart';

/// Shared read-only view over the CGPA record for screens that only care about
/// what has been completed — minors, prerequisites, course browsers.
class AcademicRecordService {
  static final AcademicRecordService _instance = AcademicRecordService._();
  factory AcademicRecordService() => _instance;
  AcademicRecordService._();

  /// Never throws: every consumer treats "no record" as a normal state, so a
  /// failure here degrades to hiding the progress UI rather than breaking the
  /// screen that asked. [CGPAService] is resolved inside the try because it
  /// touches Firestore on construction, which throws outright if Firebase
  /// isn't up yet.
  ///
  /// Deliberately not cached here. [CGPAService.loadAllCGPAData] already caches
  /// and is invalidated when the student edits their grades; a second cache
  /// would just be a second thing to go stale. Rebuilding the map is a walk
  /// over a few dozen courses.
  Future<AcademicRecord> load() async {
    try {
      final data = await CGPAService().loadAllCGPAData();
      if (data.semesters.isEmpty) return AcademicRecord.empty;

      final attempts = <String, CourseAttempt>{};
      data.latestAttempts().forEach((code, attempt) {
        attempts[AcademicRecord.normalizeCode(code)] = attempt;
      });
      return AcademicRecord(attempts: attempts, cgpa: data.cgpa);
    } catch (e) {
      SecureLogger.warning('ACADEMIC_RECORD', 'Could not load CGPA record', {
        'error': e.toString(),
      });
      return AcademicRecord.empty;
    }
  }
}
