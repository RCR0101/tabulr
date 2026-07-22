import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/minor_programme.dart';
import '../../utils/course_code.dart';
import 'courses_master_service.dart';
import '../ui/secure_logger.dart';

/// Reads and writes the `minors` collection.
///
/// The catalogue is small (about two dozen documents) and changes only when the
/// Bulletin is reissued, so it is fetched once and cached for the session
/// rather than streamed. Writes are admin-only, enforced in firestore.rules.
class MinorService {
  static final MinorService _instance = MinorService._internal();
  factory MinorService() => _instance;
  MinorService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<MinorProgramme>? _cache;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestoreCollections.minors);

  /// Drops the cache so the next read hits Firestore. Called after an admin
  /// edit so the student-facing list reflects it without a restart.
  void invalidateCache() => _cache = null;

  /// All minors, alphabetical. Returns an empty list rather than throwing so a
  /// fetch failure degrades to an empty state instead of breaking the screen.
  Future<List<MinorProgramme>> getMinors({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    try {
      final snap = await _col.orderBy('name').get();
      final minors = snap.docs.map(MinorProgramme.fromFirestore).toList();
      _cache = await _withCourseTitles(minors);
      return _cache!;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to load minors', e);
      return _cache ?? const [];
    }
  }

  /// Fills each course's title from the course master.
  ///
  /// Done here rather than at render so everything downstream — the cards, the
  /// admin editor, and `MinorProgramme.matches`, which searches titles — sees a
  /// fully populated model and needs no resolver threaded through it.
  ///
  /// A failure leaves whatever the document held, which for older records is
  /// the title the Bulletin import wrote.
  Future<List<MinorProgramme>> _withCourseTitles(
      List<MinorProgramme> minors) async {
    try {
      final master = CoursesMasterService();
      await master.loadForCampus();

      final titles = {
        for (final course in master.allCourses)
          normalizeCourseCode(course.courseCode): course.title,
      };
      if (titles.isEmpty) return minors;

      return [
        for (final minor in minors)
          minor.copyWith(groups: [
            for (final group in minor.groups)
              MinorCourseGroup(
                name: group.name,
                courses: [
                  for (final course in group.courses)
                    course.copyWith(
                      title: titles[normalizeCourseCode(course.code)] ??
                          course.title,
                    ),
                ],
              ),
          ]),
      ];
    } catch (e) {
      SecureLogger.warning('MINORS', 'Could not resolve course titles', {
        'error': e.toString(),
      });
      return minors;
    }
  }

  Future<bool> upsert(MinorProgramme minor) async {
    try {
      final data = {
        ...minor.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (minor.id.isEmpty) {
        await _col.add(data);
      } else {
        await _col.doc(minor.id).set(data, SetOptions(merge: true));
      }
      invalidateCache();
      return true;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to save minor', e);
      return false;
    }
  }

  /// Sets just the verification status without rewriting the whole document,
  /// so admins can triage from the list without opening the editor.
  Future<bool> setStatus(String id, MinorStatus status) async {
    if (id.isEmpty) return false;
    try {
      await _col.doc(id).set({
        'status': status.name,
        'needsReview': status != MinorStatus.verified,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      invalidateCache();
      return true;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to update minor status', e);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _col.doc(id).delete();
      invalidateCache();
      return true;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to delete minor', e);
      return false;
    }
  }
}
