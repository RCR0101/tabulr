import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../models/cgpa_data.dart';
import 'auth_service.dart';
import '../ui/secure_logger.dart';

class CGPAService {
  static final CGPAService _instance = CGPAService._internal();
  factory CGPAService() => _instance;
  CGPAService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Collection name for CGPA data
  static const String _collectionName = 'users';

  // Default semesters list
  static const List<String> defaultSemesters = [
    '1-1',
    '1-2',
    '2-1',
    '2-2',
    'ST 1',
    '3-1',
    '3-2',
    'ST 2',
    '4-1',
    '4-2',
    'ST 3',
    '5-1',
    '5-2',
  ];

  // Grade options for Normal courses
  static const List<String> normalGrades = [
    'A',
    'A-',
    'B',
    'B-',
    'C',
    'C-',
    'D',
    'D-',
    'E',
    'NC',
  ];

  // Grade options for ATC courses
  static const List<String> atcGrades = ['GD', 'PR', 'NC'];

  static const String _workerUrl = 'https://cgpa-encryption.dalmia-aryan.workers.dev';

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
      Uri.parse(_workerUrl),
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
      Uri.parse(_workerUrl),
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

  // Save semester data to Firestore (encrypted)
  Future<bool> saveSemesterData(
    String semesterName,
    SemesterData semesterData,
  ) async {
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
          .collection(_collectionName)
          .doc(_authService.userDocId!)
          .collection('cgpa_semesters')
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
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) return false;

      final batch = _firestore.batch();
      final colRef = _firestore
          .collection(_collectionName)
          .doc(_authService.userDocId!)
          .collection('cgpa_semesters');

      for (final entry in semesters.entries) {
        final jsonData = jsonEncode(entry.value.toJson());
        final encryptedData = await _encryptData(jsonData);
        batch.set(colRef.doc(entry.key), {
          'encryptedData': encryptedData,
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
          .collection(_collectionName)
          .doc(_authService.userDocId!)
          .collection('cgpa_semesters')
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

  Future<CGPAData> loadAllCGPAData() async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Load all CGPA data operation attempted without authentication');
        return CGPAData();
      }

      final snapshot = await _firestore
          .collection(_collectionName)
          .doc(_authService.userDocId!)
          .collection('cgpa_semesters')
          .get();

      if (snapshot.docs.isEmpty) {
        SecureLogger.info('CGPA', 'No semester data found for user');
        return CGPAData();
      }

      final semesters = <String, SemesterData>{};
      final failedSemesters = <String>[];

      final processingFutures = snapshot.docs.map((doc) async {
        try {
          final data = doc.data();
          if (data.containsKey('encryptedData')) {
            final decryptedData = await _decryptData(
              data['encryptedData'] as String,
            );
            final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;
            final semesterData = SemesterData.fromJson(jsonData);
            return MapEntry(doc.id, semesterData);
          }
          return null;
        } catch (e) {
          SecureLogger.error('CGPA', 'Failed to load semester data', e, null, {'semesterId': doc.id});
          failedSemesters.add(doc.id);
          return null;
        }
      });

      // Wait for all processing to complete
      final results = await Future.wait(processingFutures);
      
      // Add successful results to semesters map
      for (final result in results) {
        if (result != null) {
          semesters[result.key] = result.value;
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
      
      return CGPAData(semesters: semesters);
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to load all CGPA data', e);
      return CGPAData();
    }
  }

  // Delete semester data
  Future<bool> deleteSemesterData(String semesterName) async {
    try {
      final user = _authService.currentUser;
      if (user == null || _authService.userDocId == null) {
        SecureLogger.warning('CGPA', 'Delete semester data operation attempted without authentication');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(_authService.userDocId!)
          .collection('cgpa_semesters')
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
              .collection(_collectionName)
              .doc(_authService.userDocId!)
              .collection('cgpa_semesters')
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
