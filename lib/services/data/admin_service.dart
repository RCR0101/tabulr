import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import 'auth_service.dart';
import 'admin_audit_logger.dart';

class AdminService extends ChangeNotifier {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal() {
    _authService.authStateChanges.listen((user) {
      if (user != null) {
        checkAdminStatus();
      } else {
        _isAdmin = false;
        _isChecked = true;
        notifyListeners();
      }
    });
  }

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion);
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService = AuthService();
  final AdminAuditLogger _audit = AdminAuditLogger();

  static const List<int> _pdfMagic = [0x25, 0x50, 0x44, 0x46]; // %PDF

  /// Strips directory components and disallows anything outside a safe charset
  /// so a user-supplied name can't escape the intended storage folder
  /// (path traversal) or inject control characters into the object key.
  static String _sanitizeFileName(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    var cleaned = base
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), ''); // no leading dots (e.g. "..")
    if (cleaned.isEmpty) cleaned = 'upload';
    return cleaned.length > 128
        ? cleaned.substring(cleaned.length - 128)
        : cleaned;
  }

  /// Validates that [bytes] are a plausibly-safe PDF before upload. Throws
  /// [ArgumentError] otherwise. The server re-validates, but rejecting here
  /// avoids uploading junk and gives the admin immediate feedback.
  void _validatePdf(Uint8List bytes, String action) {
    if (bytes.length < 4 ||
        bytes[0] != _pdfMagic[0] ||
        bytes[1] != _pdfMagic[1] ||
        bytes[2] != _pdfMagic[2] ||
        bytes[3] != _pdfMagic[3]) {
      _audit.error(action, 'Rejected: file is not a valid PDF');
      throw ArgumentError('File is not a valid PDF');
    }
    if (bytes.length > AppLimits.maxPdfSize) {
      _audit.error(action, 'Rejected: file exceeds size limit',
          {'sizeBytes': bytes.length, 'maxBytes': AppLimits.maxPdfSize});
      throw ArgumentError('File is too large (max 10 MB)');
    }
  }

  bool _isAdmin = false;
  bool _isChecked = false;

  bool get isAdmin => _isAdmin;
  bool get isChecked => _isChecked;

  Future<bool> checkAdminStatus() async {
    if (!_authService.isAuthenticated) {
      _isAdmin = false;
      _isChecked = true;
      notifyListeners();
      return false;
    }
    try {
      final result =
          await _functions.httpsCallable('checkAdminStatus').call({});
      _isAdmin = result.data['isAdmin'] == true;
      // The function may have just (un)set the `admin` custom claim. Force a
      // token refresh so Storage rules (PDF uploads) see it this session.
      if (result.data['claimRefreshed'] == true) {
        await _authService.currentUser?.getIdToken(true);
      }
    } catch (e) {
      _isAdmin = false;
    }
    _isChecked = true;
    notifyListeners();
    return _isAdmin;
  }

  Future<String> _uploadToStorage(
      Uint8List bytes, String folder, String fileName) async {
    final safeName = _sanitizeFileName(fileName);
    final path = 'admin_uploads/$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes);
    return path;
  }

  Future<int> uploadTimetable({
    required String campusCode,
    required Uint8List fileBytes,
    required String fileName,
    List<String> excludeHeaders = const [],
    List<int>? pageRange,
    List<int>? calendarPageRange,
    int examYear = 2026,
  }) async {
    const action = 'upload_timetable';
    _validatePdf(fileBytes, action);
    final storagePath =
        await _uploadToStorage(fileBytes, 'timetable/$campusCode', fileName);
    try {
      final payload = <String, dynamic>{
        'campusCode': campusCode,
        'storagePath': storagePath,
        'excludeHeaders': excludeHeaders,
      };
      if (pageRange != null && pageRange.length == 2) {
        payload['pageRange'] = pageRange;
      }
      // Optional: parse the booklet's academic-calendar page(s) in the same
      // pass and refresh this campus's calendar. Omitted → calendar untouched.
      if (calendarPageRange != null && calendarPageRange.length == 2) {
        payload['calendarPageRange'] = calendarPageRange;
      }
      payload['examYear'] = examYear;
      final result =
          await _functions.httpsCallable('upload_timetable', options: HttpsCallableOptions(timeout: AppDurations.uploadTimetableTimeout)).call(payload);
      final uploaded = result.data['coursesUploaded'] as int;
      final calendarUploaded = (result.data['calendarEventsUploaded'] as int?) ?? 0;
      _audit.success(action, 'Uploaded $uploaded courses for $campusCode',
          {'campusCode': campusCode, 'examYear': examYear, 'calendarEvents': calendarUploaded});
      return uploaded;
    } catch (e) {
      _audit.error(action, 'Upload failed for $campusCode', e,
          {'campusCode': campusCode});
      rethrow;
    } finally {
      _storage.ref(storagePath).delete().ignore();
    }
  }

  Future<int> uploadExamSeating({
    required String campusCode,
    required Uint8List fileBytes,
    required String fileName,
    List<String> excludeHeaders = const [],
  }) async {
    const action = 'upload_exam_seating';
    _validatePdf(fileBytes, action);
    final storagePath =
        await _uploadToStorage(fileBytes, 'exam_seating/$campusCode', fileName);
    try {
      final result =
          await _functions.httpsCallable('upload_exam_seating', options: HttpsCallableOptions(timeout: AppDurations.uploadExamSeatingTimeout)).call({
        'campusCode': campusCode,
        'storagePath': storagePath,
        'excludeHeaders': excludeHeaders,
      });
      final uploaded = result.data['examsUploaded'] as int;
      _audit.success(action, 'Uploaded $uploaded exams for $campusCode',
          {'campusCode': campusCode});
      return uploaded;
    } catch (e) {
      _audit.error(action, 'Upload failed for $campusCode', e,
          {'campusCode': campusCode});
      rethrow;
    } finally {
      _storage.ref(storagePath).delete().ignore();
    }
  }

  Future<Map<String, dynamic>> rebuildProfessorSchedules({
    Uint8List? profsJsonBytes,
    String campusCode = 'hyderabad',
  }) async {
    const action = 'rebuild_professor_schedules';
    final data = <String, dynamic>{
      'campusCode': campusCode,
    };
    if (profsJsonBytes != null) {
      data['profsJsonBase64'] = base64Encode(profsJsonBytes);
    }
    try {
      final result = await _functions
          .httpsCallable('rebuildProfessorSchedules')
          .call(data);
      final map = Map<String, dynamic>.from(result.data as Map);
      _audit.success(action, 'Rebuilt professor schedules for $campusCode',
          {'campusCode': campusCode, ...map});
      return map;
    } catch (e) {
      _audit.error(action, 'Rebuild failed for $campusCode', e,
          {'campusCode': campusCode});
      rethrow;
    }
  }

  Future<Map<String, dynamic>> archiveTimetables({
    required String academicYear,
    required int semester,
  }) async {
    const action = 'archive_timetables';
    try {
      final result = await _functions
          .httpsCallable(
            'archiveTimetables',
            options: HttpsCallableOptions(
              timeout: const Duration(minutes: 9),
            ),
          )
          .call({'academicYear': academicYear, 'semester': semester});
      final map = Map<String, dynamic>.from(result.data as Map);
      _audit.success(action, 'Archived $academicYear semester $semester',
          {'academicYear': academicYear, 'semester': semester});
      return map;
    } catch (e) {
      _audit.error(action, 'Archive failed for $academicYear semester $semester',
          e, {'academicYear': academicYear, 'semester': semester});
      rethrow;
    }
  }
}
