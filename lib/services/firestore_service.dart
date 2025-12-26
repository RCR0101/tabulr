import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/timetable.dart';
import 'auth_service.dart';
import 'config_service.dart';
import 'secure_logger.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final ConfigService _config = ConfigService();

  // Collection name for user timetables (configurable via .env)
  String get _collectionName => _config.firestoreTimetablesCollection;

  Future<bool> saveTimetable(Timetable timetable) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Save operation attempted without authentication');
        return false;
      }

      // Save individual timetable as a subcollection document
      final docRef = _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .doc(timetable.id);
      
      final Map<String, dynamic> timetableData = {
        'userId': user.uid,
        'userEmail': user.email,
        'timetableData': timetable.toJson(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(timetableData, SetOptions(merge: true));

      SecureLogger.dataOperation('save', 'timetable', true, {'timetableId': timetable.id});
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to save timetable', e);
      return false;
    }
  }

  Future<Timetable?> loadTimetable() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Load operation attempted without authentication');
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        SecureLogger.info('FIRESTORE', 'No saved timetable found for user');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        SecureLogger.warning('FIRESTORE', 'Document exists but contains no data');
        return null;
      }

      final timetableData = data['timetableData'];
      if (timetableData == null) {
        SecureLogger.warning('FIRESTORE', 'No timetable data found in document');
        return null;
      }

      SecureLogger.dataOperation('load', 'timetable', true);
      return Timetable.fromJson(timetableData as Map<String, dynamic>);
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to load timetable', e);
      return null;
    }
  }

  Future<bool> deleteTimetable() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Delete operation attempted without authentication');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .delete();

      SecureLogger.dataOperation('delete', 'timetable', true);
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to delete timetable', e);
      return false;
    }
  }

  Future<DateTime?> getLastUpdated() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      final timestamp = data['lastUpdated'] as Timestamp?;
      return timestamp?.toDate();
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to get last updated time', e);
      return null;
    }
  }

  Future<bool> hasSavedTimetable() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        return false;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .get();

      return doc.exists && doc.data() != null && doc.data()!['timetableData'] != null;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to check for saved timetable', e);
      return false;
    }
  }

  Stream<DocumentSnapshot> watchTimetable() {
    final user = _authService.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection(_collectionName)
        .doc(user.uid)
        .snapshots();
  }

  // Get user's timetable metadata (without the full timetable data)
  Future<Map<String, dynamic>?> getTimetableMetadata() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return {
        'userId': data['userId'],
        'userEmail': data['userEmail'],
        'lastUpdated': data['lastUpdated'],
        'createdAt': data['createdAt'],
      };
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to get timetable metadata', e);
      return null;
    }
  }

  // Multiple timetables support
  Future<List<Timetable>> getAllTimetables() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Load timetables operation attempted without authentication');
        return [];
      }

      SecureLogger.debug('FIRESTORE', 'Loading timetables for user');

      final querySnapshot = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .orderBy('createdAt', descending: false)
          .get();

      final timetables = <Timetable>[];
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final timetableData = data['timetableData'];
          if (timetableData != null) {
            final timetable = Timetable.fromJson(timetableData as Map<String, dynamic>);
            timetables.add(timetable);
          }
        } catch (e) {
          SecureLogger.error('FIRESTORE', 'Failed to parse timetable document', e, null, {'documentId': doc.id});
        }
      }

      SecureLogger.dataOperation('load', 'timetables', true, {'count': timetables.length});
      return timetables;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to load timetables', e);
      return [];
    }
  }

  Future<Timetable?> getTimetableById(String timetableId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Get timetable by ID operation attempted without authentication');
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .doc(timetableId)
          .get();

      if (!doc.exists) {
        SecureLogger.info('FIRESTORE', 'Timetable not found', {'timetableId': timetableId});
        return null;
      }

      final data = doc.data();
      if (data == null) {
        SecureLogger.warning('FIRESTORE', 'Document exists but has no data', {'timetableId': timetableId});
        return null;
      }

      final timetableData = data['timetableData'];
      if (timetableData == null) {
        SecureLogger.warning('FIRESTORE', 'No timetable data found in document', {'timetableId': timetableId});
        return null;
      }

      SecureLogger.dataOperation('load', 'timetable', true, {'timetableId': timetableId});
      return Timetable.fromJson(timetableData as Map<String, dynamic>);
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to load timetable by ID', e, null, {'timetableId': timetableId});
      return null;
    }
  }

  Future<bool> deleteTimetableById(String timetableId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        SecureLogger.warning('FIRESTORE', 'Delete timetable operation attempted without authentication');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .doc(timetableId)
          .delete();

      SecureLogger.dataOperation('delete', 'timetable', true, {'timetableId': timetableId});
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to delete timetable by ID', e, null, {'timetableId': timetableId});
      return false;
    }
  }

  // Batch save multiple timetables (for admin use)
  Future<bool> batchSaveTimetables(Map<String, Timetable> userTimetables) async {
    try {
      final batch = _firestore.batch();

      for (final entry in userTimetables.entries) {
        final userId = entry.key;
        final timetable = entry.value;

        final docRef = _firestore.collection(_collectionName).doc(userId);
        final timetableData = {
          'userId': userId,
          'timetableData': timetable.toJson(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        };

        batch.set(docRef, timetableData, SetOptions(merge: true));
      }

      await batch.commit();
      SecureLogger.dataOperation('batch_save', 'timetables', true, {'count': userTimetables.length});
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to batch save timetables', e);
      return false;
    }
  }

  // Generic document operations for user settings
  Future<DocumentSnapshot<Map<String, dynamic>>?> getDocument(String collection, String documentId) async {
    try {
      final doc = await _firestore.collection(collection).doc(documentId).get();
      return doc;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to get document', e, null, {'collection': collection, 'documentId': documentId});
      return null;
    }
  }

  Future<bool> saveDocument(String collection, String documentId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection(collection).doc(documentId).set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to save document', e, null, {'collection': collection, 'documentId': documentId});
      return false;
    }
  }

  Future<bool> deleteDocument(String collection, String documentId) async {
    try {
      await _firestore.collection(collection).doc(documentId).delete();
      return true;
    } catch (e) {
      SecureLogger.error('FIRESTORE', 'Failed to delete document', e, null, {'collection': collection, 'documentId': documentId});
      return false;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchDocument(String collection, String documentId) {
    return _firestore.collection(collection).doc(documentId).snapshots();
  }
}