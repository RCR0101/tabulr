import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_reputation.dart';
import 'auth_service.dart';

class ReputationService {
  static final ReputationService _instance = ReputationService._internal();
  factory ReputationService() => _instance;
  ReputationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  static const String _collection = 'reputation';
  static const int _scoreFloor = -20;
  static const int _suspensionDays = 7;
  static const int _maxEvents = 50;

  DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      _firestore.collection(_collection).doc(uid);

  Future<UserReputation> getReputation(String uid) async {
    final doc = await _docRef(uid).get();
    if (!doc.exists) return UserReputation.empty(uid);
    return UserReputation.fromFirestore(doc);
  }

  Stream<UserReputation> watchReputation(String uid) {
    return _docRef(uid).snapshots().map((doc) {
      if (!doc.exists) return UserReputation.empty(uid);
      return UserReputation.fromFirestore(doc);
    });
  }

  Stream<UserReputation> watchCurrentUserReputation() {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(UserReputation.empty(''));
    return watchReputation(uid);
  }

  Future<UserReputation> getCurrentUserReputation() async {
    final uid = _authService.userDocId;
    if (uid == null) return UserReputation.empty('');
    return getReputation(uid);
  }

  Future<void> addEvent({
    required String uid,
    required String type,
    required int points,
    required String description,
    String? announcementId,
  }) async {
    final ref = _docRef(uid);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final rep = snap.exists
          ? UserReputation.fromFirestore(snap)
          : UserReputation.empty(uid);

      if (rep.isSuspended) return;

      var newScore = rep.score + points;

      DateTime? suspendedUntil = rep.suspendedUntil;
      if (newScore <= _scoreFloor) {
        newScore = 0;
        suspendedUntil = DateTime.now().add(const Duration(days: _suspensionDays));
      }

      final event = ReputationEvent(
        type: type,
        points: points,
        timestamp: DateTime.now(),
        announcementId: announcementId,
        description: description,
      );

      final events = [event, ...rep.events];
      if (events.length > _maxEvents) {
        events.removeRange(_maxEvents, events.length);
      }

      final updated = UserReputation(
        uid: uid,
        score: newScore,
        lastActive: DateTime.now(),
        suspendedUntil: suspendedUntil,
        events: events,
      );

      tx.set(ref, updated.toFirestore());
    });
  }

  Future<void> touchActivity(String uid) async {
    await _docRef(uid).set(
      {'lastActive': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
