import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/timetable.dart';
import 'auth_service.dart';
import 'campus_service.dart';

class SharedTimetableData {
  final String code;
  final String name;
  final String ownerName;
  final String campus;
  final List<SelectedSection> sections;
  final DateTime createdAt;

  SharedTimetableData({
    required this.code,
    required this.name,
    required this.ownerName,
    required this.campus,
    required this.sections,
    required this.createdAt,
  });
}

class TimetableSharingService {
  static final TimetableSharingService _instance = TimetableSharingService._internal();
  factory TimetableSharingService() => _instance;
  TimetableSharingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  static const _collection = 'shared_timetables';

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }

  Future<String> shareTimetable(Timetable timetable) async {
    final user = _authService.currentUser;
    final ownerName = user?.displayName ?? 'Anonymous';
    final campus = CampusService.currentCampus.name;

    final code = _generateUuid();
    final sectionsJson = timetable.selectedSections.map((s) => s.toJson()).toList();

    await _firestore.collection(_collection).doc(code).set({
      'name': timetable.name,
      'ownerName': ownerName,
      'ownerId': _authService.userDocId,
      'campus': campus,
      'sections': sectionsJson,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
    });

    return code;
  }

  Future<SharedTimetableData?> fetchSharedTimetable(String code) async {
    final trimmed = code.trim().toLowerCase();
    final doc = await _firestore.collection(_collection).doc(trimmed).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    final sectionsJson = data['sections'] as List<dynamic>;
    final sections = sectionsJson
        .map((s) => SelectedSection.fromJson(s as Map<String, dynamic>))
        .toList();

    return SharedTimetableData(
      code: trimmed,
      name: data['name'] as String? ?? 'Shared Timetable',
      ownerName: data['ownerName'] as String? ?? 'Unknown',
      campus: data['campus'] as String? ?? '',
      sections: sections,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
