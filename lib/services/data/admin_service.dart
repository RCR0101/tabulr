import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import 'auth_service.dart';

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
    } catch (e) {
      _isAdmin = false;
    }
    _isChecked = true;
    notifyListeners();
    return _isAdmin;
  }

  Future<String> _uploadToStorage(
      Uint8List bytes, String folder, String fileName) async {
    final path = 'admin_uploads/$folder/${DateTime.now().millisecondsSinceEpoch}_$fileName';
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
    int examYear = 2026,
  }) async {
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
      payload['examYear'] = examYear;
      final result =
          await _functions.httpsCallable('upload_timetable', options: HttpsCallableOptions(timeout: AppDurations.uploadTimetableTimeout)).call(payload);
      return result.data['coursesUploaded'] as int;
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
    final storagePath =
        await _uploadToStorage(fileBytes, 'exam_seating/$campusCode', fileName);
    try {
      final result =
          await _functions.httpsCallable('upload_exam_seating', options: HttpsCallableOptions(timeout: AppDurations.uploadExamSeatingTimeout)).call({
        'campusCode': campusCode,
        'storagePath': storagePath,
        'excludeHeaders': excludeHeaders,
      });
      return result.data['examsUploaded'] as int;
    } finally {
      _storage.ref(storagePath).delete().ignore();
    }
  }

  Future<Map<String, dynamic>> rebuildProfessorSchedules({
    Uint8List? profsJsonBytes,
    String campusCode = 'hyderabad',
  }) async {
    final data = <String, dynamic>{
      'campusCode': campusCode,
    };
    if (profsJsonBytes != null) {
      data['profsJsonBase64'] = base64Encode(profsJsonBytes);
    }
    final result = await _functions
        .httpsCallable('rebuildProfessorSchedules')
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }
}
