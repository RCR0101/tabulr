import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../constants/app_constants.dart';
import '../../models/course_history.dart';
import '../ui/secure_logger.dart';
import 'campus_service.dart';
import 'local_cache_service.dart';

/// Reads a campus's course-offering history: which courses ran in which term,
/// and who taught them.
///
/// One document per campus (`campuses/{id}/catalog/course_history`), so a cold
/// load is a single read, and it rides the campus metadata marker that timetable
/// uploads already bump — the same upload that adds a term is what invalidates
/// this cache.
class CourseHistoryService extends ChangeNotifier {
  static final CourseHistoryService _instance = CourseHistoryService._();
  factory CourseHistoryService() => _instance;
  CourseHistoryService._();

  /// Test seam: substitute an in-memory Firestore. Never set from app code.
  @visibleForTesting
  FirebaseFirestore? firestoreForTest;

  FirebaseFirestore get _firestore =>
      firestoreForTest ?? FirebaseFirestore.instance;

  final LocalCacheService _localCache = LocalCacheService();

  CourseHistory _history = CourseHistory.empty;
  bool _isLoading = false;
  String? _error;
  String? _loadedCampusId;

  CourseHistory get history => _history;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get _cacheKey => 'course_history_${CampusService.campusId}';

  DocumentReference<Map<String, dynamic>> _bundleRef(String campusId) =>
      _firestore
          .collection(FirestoreCollections.campuses)
          .doc(campusId)
          .collection(FirestoreCollections.catalog)
          .doc(FirestoreCollections.courseHistoryBundle);

  Future<void> load({bool forceRefresh = false}) async {
    final campusId = CampusService.campusId;
    if (!forceRefresh && _loadedCampusId == campusId && !_history.isEmpty) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>>? entries;
      if (!forceRefresh) {
        entries = await _localCache.readIfFresh(
          _cacheKey,
          metadataRef: CampusService.metadataDocRef(_firestore),
        );
      }

      if (entries == null) {
        entries = await _readBundle(campusId);
        if (entries != null) await _localCache.write(_cacheKey, entries);
      }

      // A campus switch starts its own load; committing a slower load for the
      // campus the user just left would overwrite the newer one's data under the
      // wrong key. Same guard CoursesMasterService needs, same reason.
      if (campusId != CampusService.campusId) return;

      _history = entries == null
          ? CourseHistory.empty
          : CourseHistory.fromBundle(entries);
      _loadedCampusId = campusId;
      SecureLogger.info('CourseHistoryService',
          'Loaded ${_history.terms.length} terms, ${_history.courses.length} courses');
    } catch (e) {
      _error = 'Failed to load course history: $e';
      _history = CourseHistory.empty;
      SecureLogger.error('CourseHistoryService', _error!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Null when no history has been recorded for this campus yet — the bundle is
  /// written by timetable uploads, so a campus uploaded before this feature
  /// existed simply has none until its next upload.
  Future<List<Map<String, dynamic>>?> _readBundle(String campusId) async {
    final doc = await _bundleRef(campusId)
        .get()
        .timeout(AppDurations.startupReadTimeout);
    if (!doc.exists) return null;
    final raw = doc.data()?['entriesJson'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final entries = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return entries.isEmpty ? null : entries;
  }

  Future<void> refresh() => load(forceRefresh: true);

  /// Fills the history in memory so widgets that read it can be tested without
  /// Firestore. Never call this from app code.
  @visibleForTesting
  void seedForTest(CourseHistory history) {
    _history = history;
    _loadedCampusId = CampusService.campusId;
    _isLoading = false;
  }
}
