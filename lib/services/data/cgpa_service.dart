import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../models/cgpa_data.dart';
import '../core/account_scoped_cache.dart';
import 'auth_service.dart';
import '../ui/secure_logger.dart';
import '../../constants/app_constants.dart';

class CGPAService {
  static final CGPAService _instance = CGPAService._internal();
  factory CGPAService() => _instance;
  CGPAService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  static const List<String> defaultSemesters = SemesterConstants.all;
  static final List<String> normalGrades = GradeConstants.normalWithReports;
  static const List<String> atcGrades = GradeConstants.atc;

  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Failed to get ID token');
    return token;
  }

  Future<String> _encryptData(String data) async {
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse(AppUrls.cgpaEncryptionWorker),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'encrypt', 'data': data}),
    );
    if (response.statusCode != 200) {
      throw Exception('Encryption failed: ${response.statusCode}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['result'] as String;
  }

  Future<String> _decryptData(String encryptedData) async {
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse(AppUrls.cgpaEncryptionWorker),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'decrypt', 'data': encryptedData}),
    );
    if (response.statusCode != 200) {
      throw Exception('Decryption failed: ${response.statusCode} ${response.body}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['result'] as String;
  }

  /// Encrypts several payloads in one request. Unlike [_decryptBatch] a partial
  /// failure throws — writing a semester with no ciphertext would drop grades.
  Future<List<String>> _encryptBatch(List<String> payloads) async {
    if (payloads.isEmpty) return const [];
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse(AppUrls.cgpaEncryptionWorker),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'encryptBatch', 'items': payloads}),
    );
    if (response.statusCode != 200) {
      throw Exception('Encryption failed: ${response.statusCode}');
    }
    final results =
        (jsonDecode(response.body) as Map<String, dynamic>)['results'] as List;
    return results.map<String>((r) {
      final entry = r as Map<String, dynamic>;
      if (entry['ok'] != true) throw Exception('Encryption failed for one item');
      return entry['result'] as String;
    }).toList();
  }

  /// Decrypts several blobs in one request, rather than one round trip per
  /// semester before the CGPA screen can render. The worker keys on the
  /// caller's own id, so a batch can only hold the caller's own data.
  ///
  /// Aligned positionally with [blobs]; null where that blob failed, so one
  /// unreadable semester doesn't lose the rest.
  Future<List<String?>> _decryptBatch(List<String> blobs) async {
    if (blobs.isEmpty) return const [];
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse(AppUrls.cgpaEncryptionWorker),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'decryptBatch', 'items': blobs}),
    );
    if (response.statusCode != 200) {
      throw Exception('Decryption failed: ${response.statusCode} ${response.body}');
    }
    final results =
        (jsonDecode(response.body) as Map<String, dynamic>)['results'] as List;
    return results.map<String?>((r) {
      final entry = r as Map<String, dynamic>;
      return entry['ok'] == true ? entry['result'] as String : null;
    }).toList();
  }

  // Save semester data to Firestore (encrypted)
  Future<bool> saveSemesterData(
    String semesterName,
    SemesterData semesterData,
  ) async {
    invalidateCache();
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Save semester data operation attempted without authentication');
        return false;
      }

      // Convert semester data to JSON
      final jsonData = jsonEncode(semesterData.toJson());

      // Encrypt the data
      final encryptedData = await _encryptData(jsonData);

      // Save to Firestore
      final docRef = _firestore
          .collection(FirestoreCollections.users)
          .doc(_authService.userDocId!)
          .collection(FirestoreCollections.cgpaSemesters)
          .doc(semesterName);

      await docRef.set({
        'encryptedData': encryptedData,
        'encryptionVersion': 2,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      SecureLogger.dataOperation('save', 'semester_data', true, {'semesterName': semesterName});
      return true;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to save semester data', e);
      return false;
    }
  }

  Future<bool> saveAllSemesters(Map<String, SemesterData> semesters) async {
    invalidateCache();
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) return false;

      final batch = _firestore.batch();
      final colRef = _firestore
          .collection(FirestoreCollections.users)
          .doc(_authService.userDocId!)
          .collection(FirestoreCollections.cgpaSemesters);

      // One request for every semester. This was already parallel, so latency
      // was fine, but it spent one worker invocation per semester.
      final entries = semesters.entries.toList();
      final ciphertexts = await _encryptBatch(
        entries.map((e) => jsonEncode(e.value.toJson())).toList(),
      );

      for (var i = 0; i < entries.length; i++) {
        batch.set(colRef.doc(entries[i].key), {
          'encryptedData': ciphertexts[i],
          'encryptionVersion': 2,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      return true;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to batch save semesters', e);
      return false;
    }
  }

  // Load semester data from Firestore (decrypted)
  Future<SemesterData?> loadSemesterData(String semesterName) async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Load semester data operation attempted without authentication');
        return null;
      }

      final docRef = _firestore
          .collection(FirestoreCollections.users)
          .doc(_authService.userDocId!)
          .collection(FirestoreCollections.cgpaSemesters)
          .doc(semesterName);

      final doc = await docRef.get();

      if (!doc.exists) {
        SecureLogger.info('CGPA', 'No saved data found for semester', {'semesterName': semesterName});
        return null;
      }

      final data = doc.data();
      if (data == null || !data.containsKey('encryptedData')) {
        SecureLogger.warning('CGPA', 'No encrypted data found in document');
        return null;
      }

      // Decrypt the data
      final decryptedData = await _decryptData(
        data['encryptedData'] as String,
      );

      // Parse JSON
      final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;

      return SemesterData.fromJson(jsonData);
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to load semester data', e);
      return null;
    }
  }

  final AccountScopedCache<CGPAData> _cachedData =
      AccountScopedCache<CGPAData>();

  void invalidateCache() => _cachedData.clear();

  Future<void> prefetch() async {
    await loadAllCGPAData();
  }

  Future<CGPAData> loadAllCGPAData() async {
    final uid = _authService.userDocId;
    if (uid == null) {
      SecureLogger.warning(
          'CGPA', 'Load all CGPA data operation attempted without authentication');
      return CGPAData();
    }
    final cached = _cachedData.read(uid);
    if (cached != null) return cached;
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('CGPA', 'Load all CGPA data operation attempted without authentication');
        return CGPAData();
      }

      final snapshot = await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .collection(FirestoreCollections.cgpaSemesters)
          .get();

      if (snapshot.docs.isEmpty) {
        SecureLogger.info('CGPA', 'No semester data found for user');
        final empty = CGPAData();
        _cachedData.write(uid, empty);
        return empty;
      }

      final semesters = <String, SemesterData>{};
      final failedSemesters = <String>[];

      // Docs with no `encryptedData` are dropped first so the batch stays
      // positionally aligned with `encrypted`.
      final encrypted = snapshot.docs
          .where((doc) => doc.data().containsKey('encryptedData'))
          .toList();
      final plaintexts = await _decryptBatch(
        encrypted.map((doc) => doc.data()['encryptedData'] as String).toList(),
      );

      for (var i = 0; i < encrypted.length; i++) {
        final docId = encrypted[i].id;
        final plaintext = plaintexts[i];
        if (plaintext == null) {
          SecureLogger.error('CGPA', 'Failed to decrypt semester data', null,
              null, {'semesterId': docId});
          failedSemesters.add(docId);
          continue;
        }
        try {
          semesters[docId] = SemesterData.fromJson(
              jsonDecode(plaintext) as Map<String, dynamic>);
        } catch (e) {
          // Decrypted but didn't parse — still per-semester, not fatal.
          SecureLogger.error('CGPA', 'Failed to parse semester data', e, null,
              {'semesterId': docId});
          failedSemesters.add(docId);
        }
      }

      if (failedSemesters.isNotEmpty) {
        SecureLogger.warning('CGPA', 'Some semester data failed to load', {
          'failedSemesters': failedSemesters,
          'totalAttempted': snapshot.docs.length,
          'successful': semesters.length,
        });
      }

      SecureLogger.dataOperation('load', 'all_semester_data', true, {
        'semesterCount': semesters.length,
        'failedCount': failedSemesters.length,
        'totalDocuments': snapshot.docs.length,
      });
      
      final data = CGPAData(semesters: semesters);
      _cachedData.write(uid, data);
      return data;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to load all CGPA data', e);
      return CGPAData();
    }
  }

  // Delete semester data
  Future<bool> deleteSemesterData(String semesterName) async {
    invalidateCache();
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Delete semester data operation attempted without authentication');
        return false;
      }

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(_authService.userDocId!)
          .collection(FirestoreCollections.cgpaSemesters)
          .doc(semesterName)
          .delete();

      SecureLogger.dataOperation('delete', 'semester_data', true, {'semesterName': semesterName});
      return true;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to delete semester data', e);
      return false;
    }
  }

  // Delete all CGPA data for the user
  Future<bool> deleteAllCGPAData() async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Delete all CGPA data operation attempted without authentication');
        return false;
      }

      final snapshot =
          await _firestore
              .collection(FirestoreCollections.users)
              .doc(_authService.userDocId!)
              .collection(FirestoreCollections.cgpaSemesters)
              .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      SecureLogger.dataOperation('delete', 'all_cgpa_data', true);
      return true;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to delete all CGPA data', e);
      return false;
    }
  }
}
