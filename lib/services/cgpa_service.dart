import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../models/cgpa_data.dart';
import 'auth_service.dart';
import 'secure_logger.dart';

class CGPAService {
  static final CGPAService _instance = CGPAService._internal();
  factory CGPAService() => _instance;
  CGPAService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Collection name for CGPA data
  static const String _collectionName = 'cgpa';

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

  // Generate encryption key from user ID
  String _generateEncryptionKey(String userId) {
    // Use HMAC-SHA256 to derive a consistent key from user ID
    final key = utf8.encode('tabulr_cgpa_encryption_key_v1');
    final bytes = utf8.encode(userId);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  // Encrypt data using simple XOR cipher (for basic obfuscation)
  String _encryptData(String data, String userId) {
    try {
      final key = _generateEncryptionKey(userId);
      final dataBytes = utf8.encode(data);
      final keyBytes = utf8.encode(key);

      final encrypted = <int>[];
      for (int i = 0; i < dataBytes.length; i++) {
        encrypted.add(dataBytes[i] ^ keyBytes[i % keyBytes.length]);
      }

      return base64Encode(encrypted);
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to encrypt data', e);
      rethrow;
    }
  }

  // Decrypt data
  String _decryptData(String encryptedData, String userId) {
    try {
      final key = _generateEncryptionKey(userId);
      final encrypted = base64Decode(encryptedData);
      final keyBytes = utf8.encode(key);

      final decrypted = <int>[];
      for (int i = 0; i < encrypted.length; i++) {
        decrypted.add(encrypted[i] ^ keyBytes[i % keyBytes.length]);
      }

      return utf8.decode(decrypted);
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to decrypt data', e);
      rethrow;
    }
  }

  // Save semester data to Firestore (encrypted)
  Future<bool> saveSemesterData(
    String semesterName,
    SemesterData semesterData,
  ) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('CGPA', 'Save semester data operation attempted without authentication');
        return false;
      }

      // Convert semester data to JSON
      final jsonData = jsonEncode(semesterData.toJson());

      // Encrypt the data
      final encryptedData = _encryptData(jsonData, user.uid);

      // Save to Firestore
      final docRef = _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('semesters')
          .doc(semesterName);

      await docRef.set({
        'encryptedData': encryptedData,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      SecureLogger.dataOperation('save', 'semester_data', true, {'semesterName': semesterName});
      return true;
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to save semester data', e);
      return false;
    }
  }

  // Load semester data from Firestore (decrypted)
  Future<SemesterData?> loadSemesterData(String semesterName) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('CGPA', 'Load semester data operation attempted without authentication');
        return null;
      }

      final docRef = _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('semesters')
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
      final decryptedData = _decryptData(
        data['encryptedData'] as String,
        user.uid,
      );

      // Parse JSON
      final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;

      return SemesterData.fromJson(jsonData);
    } catch (e) {
      SecureLogger.error('CGPA', 'Failed to load semester data', e);
      return null;
    }
  }

  // Load all semester data for the user
  Future<CGPAData> loadAllCGPAData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('CGPA', 'Load all CGPA data operation attempted without authentication');
        return CGPAData();
      }

      final snapshot =
          await _firestore
              .collection(_collectionName)
              .doc(user.uid)
              .collection('semesters')
              .get();

      final semesters = <String, SemesterData>{};

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          if (data.containsKey('encryptedData')) {
            final decryptedData = _decryptData(
              data['encryptedData'] as String,
              user.uid,
            );
            final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;
            final semesterData = SemesterData.fromJson(jsonData);
            semesters[doc.id] = semesterData;
          }
        } catch (e) {
          SecureLogger.error('CGPA', 'Failed to load semester data', e, null, {'semesterId': doc.id});
        }
      }

      SecureLogger.dataOperation('load', 'all_semester_data', true, {'semesterCount': semesters.length});
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
      if (user == null) {
        SecureLogger.warning('CGPA', 'Delete semester data operation attempted without authentication');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('semesters')
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
      if (user == null) {
        SecureLogger.warning('CGPA', 'Delete all CGPA data operation attempted without authentication');
        return false;
      }

      final snapshot =
          await _firestore
              .collection(_collectionName)
              .doc(user.uid)
              .collection('semesters')
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
