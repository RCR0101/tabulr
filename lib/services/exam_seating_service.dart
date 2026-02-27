import 'package:cloud_firestore/cloud_firestore.dart';
import 'campus_service.dart';
import 'auth_service.dart';

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
    if (data == null) {
      return ExamSeating(
        courseCode: doc.id,
        courseTitle: '',
        examDate: '',
        rooms: [],
      );
    }

    final roomsList = (data['rooms'] as List<dynamic>?)
            ?.map((r) => ExamRoom.fromMap(r as Map<String, dynamic>))
            .toList() ??
        [];

    return ExamSeating(
      courseCode: data['courseCode'] ?? doc.id,
      courseTitle: data['courseTitle'] ?? '',
      examDate: data['examDate'] ?? '',
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

  /// Get the collection name based on current campus
  String get _collectionName {
    switch (CampusService.currentCampus) {
      case Campus.hyderabad:
        return 'hyd-exam-seating';
      case Campus.pilani:
        return 'pilani-exam-seating';
      case Campus.goa:
        return 'goa-exam-seating';
    }
  }

  /// Fetch all exam seating data
  Future<List<ExamSeating>> fetchAllExamSeating() async {
    try {
      final querySnapshot = await _firestore.collection(_collectionName).get();

      return querySnapshot.docs
          .map((doc) => ExamSeating.fromFirestore(doc))
          .where((exam) => exam.rooms.isNotEmpty)
          .toList();
    } catch (e) {
      print('Error fetching exam seating: $e');
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
      print('Error searching exam seating: $e');
      return [];
    }
  }

  /// Get a specific exam by course code
  Future<ExamSeating?> getExamByCourseCode(String courseCode) async {
    try {
      final docId = courseCode.replaceAll(' ', '_');
      final doc = await _firestore.collection(_collectionName).doc(docId).get();

      if (!doc.exists) return null;

      return ExamSeating.fromFirestore(doc);
    } catch (e) {
      print('Error fetching exam: $e');
      return null;
    }
  }

  /// Find room for a student in a specific course
  Future<ExamRoom?> findRoomForStudent(
      String courseCode, String studentId) async {
    final exam = await getExamByCourseCode(courseCode);
    return exam?.findRoomForStudent(studentId);
  }

  // User data collection name
  static const String _userCollectionName = 'exam-seating-user';

  final AuthService _authService = AuthService();

  /// Save user's exam seating preferences (selected courses and student ID)
  Future<bool> saveUserData({
    required List<String> selectedCourseCodes,
    required String studentId,
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        return false;
      }

      final docRef = _firestore.collection(_userCollectionName).doc(user.uid);

      await docRef.set({
        'selectedCourseCodes': selectedCourseCodes,
        'studentId': studentId,
        'campus': CampusService.currentCampus.name,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error saving exam seating user data: $e');
      return false;
    }
  }

  /// Load user's exam seating preferences
  Future<ExamSeatingUserData?> loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        return null;
      }

      final docRef = _firestore.collection(_userCollectionName).doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return ExamSeatingUserData.fromMap(data);
    } catch (e) {
      print('Error loading exam seating user data: $e');
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
      selectedCourseCodes: List<String>.from(map['selectedCourseCodes'] ?? []),
      studentId: map['studentId'] ?? '',
      campus: map['campus'],
    );
  }
}
