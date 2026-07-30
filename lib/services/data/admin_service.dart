import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import 'auth_service.dart';
import 'admin_audit_logger.dart';

/// What an upload would change, from a dry run that wrote nothing.
class TimetablePreview {
  const TimetablePreview({
    required this.parsed,
    required this.live,
    required this.added,
    required this.removed,
    required this.changed,
    required this.unchanged,
    required this.addedSample,
    required this.removedSample,
    required this.changedSample,
    required this.problems,
    required this.parserVersion,
    required this.term,
  });

  final int parsed;
  final int live;
  final int added;
  final int removed;
  final int changed;
  final int unchanged;
  final List<String> addedSample;
  final List<String> removedSample;
  final List<String> changedSample;

  /// Structural defects that mean the columns were misread — a credit string
  /// parsed as a title, and so on. Non-empty here means the real upload will
  /// be refused unless forced.
  final List<String> problems;

  /// Git sha of the deployed parser, so the diff can be attributed to code.
  final String parserVersion;

  /// The term this booklet will be filed under in the course-history record,
  /// e.g. `2026-27-1`. Shown in the confirmation because it is derived from the
  /// exam year and semester rather than read off the PDF, and a wrong term
  /// mislabels a whole semester of history with nothing else to catch it.
  final String? term;

  static List<String> _strings(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory TimetablePreview.fromMap(Map<String, dynamic> m) => TimetablePreview(
        parsed: (m['parsed'] as num?)?.toInt() ?? 0,
        live: (m['live'] as num?)?.toInt() ?? 0,
        added: (m['added'] as num?)?.toInt() ?? 0,
        removed: (m['removed'] as num?)?.toInt() ?? 0,
        changed: (m['changed'] as num?)?.toInt() ?? 0,
        unchanged: (m['unchanged'] as num?)?.toInt() ?? 0,
        addedSample: _strings(m['addedSample']),
        removedSample: _strings(m['removedSample']),
        changedSample: _strings(m['changedSample']),
        problems: _strings(m['problems']),
        parserVersion: (m['parserVersion'] ?? 'unknown').toString(),
        term: m['term'] as String?,
      );

  /// A first upload has nothing to compare against, so a big diff is expected.
  bool get isFirstUpload => live == 0;

  /// Worth a second look even when nothing is structurally broken: replacing
  /// most of the collection is what a bad page range looks like.
  bool get isDisruptive =>
      !isFirstUpload && (removed + changed) > (live * 0.5);
}

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

  /// Parses the PDF and reports what an upload would change, writing nothing.
  ///
  /// A course total cannot tell "the registrar moved two labs" apart from "the
  /// columns shifted and every row is subtly wrong" — both come back 377. This
  /// is what puts the actual diff in front of the admin before they commit it.
  Future<TimetablePreview> previewTimetable({
    required String campusCode,
    required Uint8List fileBytes,
    required String fileName,
    List<String> excludeHeaders = const [],
    List<int>? pageRange,
    int examYear = 2026,
    required int semester,
  }) async {
    const action = 'preview_timetable';
    _validatePdf(fileBytes, action);
    final storagePath =
        await _uploadToStorage(fileBytes, 'timetable/$campusCode', fileName);
    try {
      final payload = <String, dynamic>{
        'campusCode': campusCode,
        'storagePath': storagePath,
        'excludeHeaders': excludeHeaders,
        'examYear': examYear,
        'semester': semester,
        'dryRun': true,
      };
      if (pageRange != null && pageRange.length == 2) {
        payload['pageRange'] = pageRange;
      }
      final result = await _functions
          .httpsCallable('upload_timetable',
              options: HttpsCallableOptions(
                  timeout: AppDurations.uploadTimetableTimeout))
          .call(payload);
      return TimetablePreview.fromMap(
          Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      _audit.error(action, 'Preview failed for $campusCode', e,
          {'campusCode': campusCode});
      rethrow;
    } finally {
      _storage.ref(storagePath).delete().ignore();
    }
  }

  Future<int> uploadTimetable({
    required String campusCode,
    required Uint8List fileBytes,
    required String fileName,
    List<String> excludeHeaders = const [],
    List<int>? pageRange,
    List<int>? calendarPageRange,
    int examYear = 2026,
    required int semester,
    bool force = false,
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
      // Files this booklet's term in the course-history record, and picks the
      // semester for the calendar parse instead of leaving it to be guessed
      // from the page heading.
      payload['semester'] = semester;
      payload['calendarSemester'] = semester;
      // The backend refuses an upload that would drop most of the collection —
      // usually a bad page range rather than a real change. This is the
      // acknowledged override; without it the refusal is a dead end.
      if (force) payload['force'] = true;
      final result =
          await _functions.httpsCallable('upload_timetable', options: HttpsCallableOptions(timeout: AppDurations.uploadTimetableTimeout)).call(payload);
      final uploaded = result.data['coursesUploaded'] as int;
      final calendarUploaded = (result.data['calendarEventsUploaded'] as int?) ?? 0;
      _audit.success(action, 'Uploaded $uploaded courses for $campusCode', {
        'campusCode': campusCode,
        'examYear': examYear,
        'term': result.data['term'],
        'historyRecorded': result.data['historyRecorded'],
        'calendarEvents': calendarUploaded,
      });
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
