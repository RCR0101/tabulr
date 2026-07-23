import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/academic_calendar_event.dart';
import '../ui/secure_logger.dart';
import 'campus_service.dart';
import 'local_cache_service.dart';

/// Reads a campus's academic calendar (holidays, deadlines, exam windows)
/// written by the `upload_timetable` Cloud Function and curated in the admin
/// review screen. Loads are cached per campus so the calendar overlay and the
/// ICS export can read synchronously after a one-time fetch.
class AcademicCalendarService {
  static final AcademicCalendarService _instance =
      AcademicCalendarService._internal();
  factory AcademicCalendarService() => _instance;
  AcademicCalendarService._internal();

  final LocalCacheService _localCache = LocalCacheService();

  /// campusId → its events, sorted by date. Absent until loaded.
  final Map<String, List<AcademicCalendarEvent>> _byCampus = {};

  static String _cacheKey(String campusId) => 'academic_calendar_$campusId';

  DocumentReference<Map<String, dynamic>> _docRef(String campusId) =>
      FirebaseFirestore.instance
          .collection(FirestoreCollections.campuses)
          .doc(campusId)
          .collection(FirestoreCollections.academicCalendar)
          .doc(FirestoreCollections.current);

  /// Events already loaded for [campusId], or an empty list if not yet loaded.
  List<AcademicCalendarEvent> eventsFor([String? campusId]) =>
      _byCampus[campusId ?? CampusService.campusId] ?? const [];

  bool isLoaded([String? campusId]) =>
      _byCampus.containsKey(campusId ?? CampusService.campusId);

  /// Load the calendar for [campusId] (defaults to the current campus), falling
  /// back to the local cache when offline. Idempotent unless [force].
  Future<List<AcademicCalendarEvent>> load({
    String? campusId,
    bool force = false,
  }) async {
    final id = campusId ?? CampusService.campusId;
    if (!force && _byCampus.containsKey(id)) return _byCampus[id]!;
    try {
      final snap = await _docRef(id).get();
      final data = snap.data();
      final raw = data?['events'];
      if (raw is List) {
        final events = _parse(raw);
        _byCampus[id] = events;
        await _localCache.write(_cacheKey(id), raw.cast<Map<String, dynamic>>());
        return events;
      }
      // Doc missing or empty: an unconfigured campus. Cache the empty state so
      // callers don't refetch on every render.
      _byCampus[id] = const [];
      return const [];
    } catch (e) {
      SecureLogger.error('ACADEMIC_CALENDAR', 'Failed to load calendar for $id', e);
      final cached = await _localCache.read(_cacheKey(id));
      final events = cached == null ? const <AcademicCalendarEvent>[] : _parse(cached);
      _byCampus[id] = events;
      return events;
    }
  }

  List<AcademicCalendarEvent> _parse(List<dynamic> raw) {
    final events = <AcademicCalendarEvent>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          events.add(AcademicCalendarEvent.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // Skip a malformed row rather than failing the whole calendar.
        }
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  /// Persist the admin-reviewed [events] for [campusId] and apply them
  /// in-memory immediately.
  Future<void> save(String campusId, List<AcademicCalendarEvent> events) async {
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));
    final json = [for (final e in sorted) e.toJson()];
    await _docRef(campusId).set({
      'events': json,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    _byCampus[campusId] = sorted;
    await _localCache.write(_cacheKey(campusId), json);
  }
}
