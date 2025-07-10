import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/timetable.dart';
import 'auth_service.dart';
import 'config_service.dart';

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
        print('User not authenticated, cannot save timetable');
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

      print('Timetable ${timetable.id} saved successfully for user: ${user.email}');
      return true;
    } catch (e) {
      print('Error saving timetable: $e');
      return false;
    }
  }

  Future<Timetable?> loadTimetable() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('User not authenticated, cannot load timetable');
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        print('No saved timetable found for user: ${user.email}');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        print('Document exists but has no data for user: ${user.email}');
        return null;
      }

      final timetableData = data['timetableData'];
      if (timetableData == null) {
        print('No timetable data found in document for user: ${user.email}');
        return null;
      }

      print('Timetable loaded successfully for user: ${user.email}');
      return Timetable.fromJson(timetableData as Map<String, dynamic>);
    } catch (e) {
      print('Error loading timetable: $e');
      return null;
    }
  }

  Future<bool> deleteTimetable() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('User not authenticated, cannot delete timetable');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .delete();

      print('Timetable deleted successfully for user: ${user.email}');
      return true;
    } catch (e) {
      print('Error deleting timetable: $e');
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
      print('Error getting last updated time: $e');
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
      print('Error checking for saved timetable: $e');
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
      print('Error getting timetable metadata: $e');
      return null;
    }
  }

  // Multiple timetables support
  Future<List<Timetable>> getAllTimetables() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('User not authenticated, cannot load timetables');
        return [];
      }

      print('🔥 FIRESTORE READ: Loading timetables for user: ${user.uid}');

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
          print('Error parsing timetable ${doc.id}: $e');
        }
      }

      print('Loaded ${timetables.length} timetables from Firestore for user: ${user.email}');
      return timetables;
    } catch (e) {
      print('Error loading timetables: $e');
      return [];
    }
  }

  Future<Timetable?> getTimetableById(String timetableId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('User not authenticated, cannot load timetable');
        return null;
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .doc(timetableId)
          .get();

      if (!doc.exists) {
        print('Timetable $timetableId not found for user: ${user.email}');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        print('Document exists but has no data for timetable: $timetableId');
        return null;
      }

      final timetableData = data['timetableData'];
      if (timetableData == null) {
        print('No timetable data found in document for timetable: $timetableId');
        return null;
      }

      print('Timetable $timetableId loaded successfully for user: ${user.email}');
      return Timetable.fromJson(timetableData as Map<String, dynamic>);
    } catch (e) {
      print('Error loading timetable $timetableId: $e');
      return null;
    }
  }

  Future<bool> deleteTimetableById(String timetableId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('User not authenticated, cannot delete timetable');
        return false;
      }

      await _firestore
          .collection(_collectionName)
          .doc(user.uid)
          .collection('timetables')
          .doc(timetableId)
          .delete();

      print('Timetable $timetableId deleted successfully for user: ${user.email}');
      return true;
    } catch (e) {
      print('Error deleting timetable $timetableId: $e');
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
      print('Batch save completed for ${userTimetables.length} timetables');
      return true;
    } catch (e) {
      print('Error in batch save: $e');
      return false;
    }
  }
}