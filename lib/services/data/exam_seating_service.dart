import 'package:cloud_firestore/cloud_firestore.dart';
import 'campus_service.dart';
import 'auth_service.dart';
import 'courses_master_service.dart';
import '../ui/secure_logger.dart';

/// Represents a room with its ID range for exam seating
class ExamRoom {
  final String roomNo;
  final String? idFrom;
  final String? idTo;
  final int? studentCount;
  final bool allStudents;

  ExamRoom({
    required this.roomNo,
    this.idFrom,
    this.idTo,
    this.studentCount,
    this.allStudents = false,
  });

  factory ExamRoom.fromMap(Map<String, dynamic> map) {
    final idFrom = map['idFrom'];
    final idTo = map['idTo'];
    final isAllStudents = (idFrom == null || idFrom.toString().isEmpty) &&
        (idTo == null || idTo.toString().isEmpty);

    return ExamRoom(
      roomNo: map['roomNo'] ?? '',
      idFrom: idFrom?.toString(),
      idTo: idTo?.toString(),
      studentCount: map['studentCount'],
      allStudents: isAllStudents,
    );
  }

  /// Check if a student ID falls within this room's range using lexicographic comparison
  /// If allStudents is true, this room matches any student ID
  bool containsStudentId(String studentId) {
    // If this room is for all students, it always matches
    if (allStudents || (idFrom == null && idTo == null)) {
      return true;
    }

    final normalizedId = studentId.toUpperCase().trim();
    final normalizedFrom = (idFrom ?? '').toUpperCase().trim();
    final normalizedTo = (idTo ?? '').toUpperCase().trim();

    // If either bound is empty, we can't do range comparison
    if (normalizedFrom.isEmpty || normalizedTo.isEmpty) {
      return true; // Treat as all students
    }

    return normalizedId.compareTo(normalizedFrom) >= 0 &&
        normalizedId.compareTo(normalizedTo) <= 0;
  }
}

/// Represents an exam with course details and room assignments
class ExamSeating {
  final String courseCode;
  final String courseTitle;
  final String examDate;
  final List<ExamRoom> rooms;

  ExamSeating({
    required this.courseCode,
    required this.courseTitle,
    required this.examDate,
    required this.rooms,
  });

  factory ExamSeating.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final code = doc.id.replaceAll('_', ' ');
    if (data == null) {
      return ExamSeating(
        courseCode: code,
        courseTitle: CoursesMasterService().getTitle(code),
        examDate: '',
        rooms: [],
      );
    }

    final roomsList = (data['rooms'] as List<dynamic>?)
            ?.map((r) => ExamRoom.fromMap(r as Map<String, dynamic>))
            .toList() ??
        [];

    final examDate = data['exam_date'];
    String examDateStr = '';
    if (examDate is String) {
      examDateStr = examDate;
    } else if (examDate != null && examDate.toDate != null) {
      examDateStr = examDate.toDate().toIso8601String();
    }

    return ExamSeating(
      courseCode: code,
      courseTitle: CoursesMasterService().getTitle(code),
      examDate: examDateStr,
      rooms: roomsList,
    );
  }

  /// Find the room for a given student ID
  ExamRoom? findRoomForStudent(String studentId) {
    for (final room in rooms) {
      if (room.containsStudentId(studentId)) {
        return room;
      }
    }
    return null;
  }
}

/// Service for fetching exam seating data from Firestore
class ExamSeatingService {
  static final ExamSeatingService _instance = ExamSeatingService._internal();
  factory ExamSeatingService() => _instance;
  ExamSeatingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<ExamSeating>? _cachedExams;

  void invalidateCache() => _cachedExams = null;

  CollectionReference<Map<String, dynamic>> get _collectionRef =>
      CampusService.examSeatingRef(_firestore);

  Future<List<ExamSeating>> fetchAllExamSeating() async {
    if (_cachedExams != null) return _cachedExams!;

    try {
      final querySnapshot = await _collectionRef.get();

      _cachedExams = querySnapshot.docs
          .map((doc) => ExamSeating.fromFirestore(doc))
          .where((exam) => exam.rooms.isNotEmpty)
          .toList();
      return _cachedExams!;
    } catch (e) {
      SecureLogger.error('EXAM_SEATING', 'Error fetching exam seating', e);
      return [];
    }
  }

  /// Search for exams by course code
  Future<List<ExamSeating>> searchByCourseCode(String query) async {
    if (query.isEmpty) return [];

    try {
      final allExams = await fetchAllExamSeating();
      final normalizedQuery = query.toUpperCase().trim();

      return allExams
          .where((exam) =>
              exam.courseCode.toUpperCase().contains(normalizedQuery) ||
              exam.courseTitle.toUpperCase().contains(normalizedQuery))
          .toList();
    } catch (e) {
      SecureLogger.error('EXAM_SEATING', 'Error searching exam seating', e);
      return [];
    }
  }

  /// Get a specific exam by course code
  Future<ExamSeating?> getExamByCourseCode(String courseCode) async {
    try {
      final docId = courseCode.replaceAll(' ', '_');
      final doc = await _collectionRef.doc(docId).get();

      if (!doc.exists) return null;

      return ExamSeating.fromFirestore(doc);
    } catch (e) {
      SecureLogger.error('EXAM_SEATING', 'Error fetching exam', e);
      return null;
    }
  }

  /// Find room for a student in a specific course
  Future<ExamRoom?> findRoomForStudent(
      String courseCode, String studentId) async {
    final exam = await getExamByCourseCode(courseCode);
    return exam?.findRoomForStudent(studentId);
  }

  final AuthService _authService = AuthService();

  DocumentReference<Map<String, dynamic>> _userPrefsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('exam_seating_prefs').doc('data');

  Future<bool> saveUserData({
    required List<String> selectedCourseCodes,
    required String studentId,
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        return false;
      }

      await _userPrefsRef(_authService.userDocId!).set({
        'selected_course_codes': selectedCourseCodes,
        'student_id': studentId,
        'campus': CampusService.currentCampus.name,
        'last_updated': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      SecureLogger.error('EXAM_SEATING', 'Error saving user data', e);
      return false;
    }
  }

  Future<ExamSeatingUserData?> loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        return null;
      }

      final doc = await _userPrefsRef(_authService.userDocId!).get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return ExamSeatingUserData.fromMap(data);
    } catch (e) {
      SecureLogger.error('EXAM_SEATING', 'Error loading user data', e);
      return null;
    }
  }
}

/// Represents user's saved exam seating preferences
class ExamSeatingUserData {
  final List<String> selectedCourseCodes;
  final String studentId;
  final String? campus;

  ExamSeatingUserData({
    required this.selectedCourseCodes,
    required this.studentId,
    this.campus,
  });

  factory ExamSeatingUserData.fromMap(Map<String, dynamic> map) {
    return ExamSeatingUserData(
      selectedCourseCodes: List<String>.from(map['selected_course_codes'] ?? []),
      studentId: map['student_id'] ?? '',
      campus: map['campus'],
    );
  }
}
