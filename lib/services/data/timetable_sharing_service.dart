import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/timetable.dart';
import 'auth_service.dart';
import 'campus_service.dart';
import '../../constants/app_constants.dart';

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

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }

  String generateShareId() => _generateUuid();

  Future<void> uploadShare(String code, Timetable timetable) async {
    final user = _authService.currentUser;
    final ownerName = user?.displayName ?? 'Anonymous';
    final campus = CampusService.currentCampus.name;
    final sectionsJson = timetable.selectedSections.map((s) => s.toJson()).toList();

    await _firestore.collection(FirestoreCollections.sharedTimetables).doc(code).set({
      'name': timetable.name,
      'ownerName': ownerName,
      'ownerId': _authService.userDocId,
      'campus': campus,
      'sections': sectionsJson,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> revokeAndReshare(Timetable timetable) async {
    if (timetable.shareId != null) {
      try {
        await _firestore.collection(FirestoreCollections.sharedTimetables).doc(timetable.shareId).delete();
      } catch (_) {}
    }

    final newCode = _generateUuid();
    await uploadShare(newCode, timetable);
    return newCode;
  }

  Future<void> deleteShare(String shareId) async {
    await _firestore.collection(FirestoreCollections.sharedTimetables).doc(shareId).delete();
  }

  static String _sanitize(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
        .replaceAll(RegExp(r'on\w+=', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();
  }

  static String _sanitizeCode(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '').toLowerCase();
  }

  Future<SharedTimetableData?> fetchSharedTimetable(String code) async {
    final trimmed = _sanitizeCode(code);
    if (trimmed.isEmpty) return null;
    final doc = await _firestore.collection(FirestoreCollections.sharedTimetables).doc(trimmed).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    final sectionsRaw = data['sections'] as List<dynamic>? ?? [];
    final sections = <SelectedSection>[];
    for (final s in sectionsRaw) {
      final map = Map<String, dynamic>.from(s as Map);
      if (map['section'] is Map) {
        map['section'] = Map<String, dynamic>.from(map['section'] as Map);
        if (map['section']['schedule'] is List) {
          map['section']['schedule'] = (map['section']['schedule'] as List)
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
              .toList();
        }
      }
      sections.add(SelectedSection.fromJson(map));
    }

    return SharedTimetableData(
      code: trimmed,
      name: _sanitize(data['name'] as String? ?? 'Shared Timetable'),
      ownerName: _sanitize(data['ownerName'] as String? ?? 'Unknown'),
      campus: _sanitize(data['campus'] as String? ?? ''),
      sections: sections,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
