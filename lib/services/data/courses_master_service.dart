import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'campus_service.dart';
import 'local_cache_service.dart';
import '../../constants/app_constants.dart';

class CourseMasterEntry {
  final String courseCode;
  final String title;
  final double credits;
  final String type;

  CourseMasterEntry({
    required this.courseCode,
    required this.title,
    required this.credits,
    required this.type,
  });

  factory CourseMasterEntry.fromMap(Map<String, dynamic> map) {
    return CourseMasterEntry(
      courseCode: map['course_code'] ?? '',
      title: map['title'] ?? '',
      credits: (map['credits'] as num?)?.toDouble() ?? 0,
      type: map['type'] ?? 'Normal',
    );
  }
}

class CoursesMasterService {
  static final CoursesMasterService _instance = CoursesMasterService._();
  factory CoursesMasterService() => _instance;
  CoursesMasterService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalCacheService _localCache = LocalCacheService();

  Map<String, CourseMasterEntry> _cache = {};
  bool _loaded = false;
  bool _loading = false;

  final StreamController<bool> _loadStateController =
      StreamController<bool>.broadcast();

  Stream<bool> get loadStateStream => _loadStateController.stream;

  String get _cacheKey => 'courses_master_${CampusService.campusId}';

  Future<void> loadForCampus({bool forceRefresh = false}) async {
    if (_loading) return;
    if (_loaded && !forceRefresh) return;
    _loading = true;
    _loadStateController.add(false);

    final campusId = CampusService.campusId;

    if (!forceRefresh) {
      final cached = await _localCache.readIfFresh(
        _cacheKey,
        metadataRef: CampusService.metadataDocRef(_firestore),
      );
      if (cached != null) {
        _cache = {
          for (final map in cached)
            map['course_code'] as String: CourseMasterEntry.fromMap(map)
        };
        _loaded = true;
        _loading = false;
        _loadStateController.add(true);
        return;
      }
    }

    final snapshot = await _firestore
        .collection(FirestoreCollections.campuses)
        .doc(campusId)
        .collection(FirestoreCollections.coursesMaster)
        .get();

    final docs = snapshot.docs.map((doc) => doc.data()).toList();
    _cache = {
      for (final map in docs)
        map['course_code'] as String: CourseMasterEntry.fromMap(map)
    };

    await _localCache.write(_cacheKey, docs);
    _loaded = true;
    _loading = false;
    _loadStateController.add(true);
  }

  String getTitle(String courseCode) {
    return _cache[courseCode]?.title ?? courseCode;
  }

  CourseMasterEntry? get(String courseCode) => _cache[courseCode];

  List<CourseMasterEntry> get allCourses => _cache.values.toList();

  bool get isLoaded => _loaded;

  void clear() {
    _cache = {};
    _loaded = false;
    _loading = false;
    _localCache.invalidate(_cacheKey);
  }
}
