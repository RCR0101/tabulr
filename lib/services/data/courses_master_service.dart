import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'campus_service.dart';
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

  Map<String, CourseMasterEntry> _cache = {};
  bool _loaded = false;
  bool _loading = false;

  final StreamController<bool> _loadStateController =
      StreamController<bool>.broadcast();

  Stream<bool> get loadStateStream => _loadStateController.stream;

  Future<void> loadForCampus() async {
    if (_loading) return;
    _loading = true;
    _loaded = false;
    _loadStateController.add(false);

    final campusId = CampusService.campusId;
    final snapshot = await _firestore
        .collection(FirestoreCollections.campuses)
        .doc(campusId)
        .collection(FirestoreCollections.coursesMaster)
        .get();

    _cache = {
      for (final doc in snapshot.docs)
        doc.data()['course_code'] as String: CourseMasterEntry.fromMap(doc.data())
    };

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
  }
}
