import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/user_reputation.dart';
import 'auth_service.dart';
import '../../constants/app_constants.dart';

class ReputationService {
  static final ReputationService _instance = ReputationService._internal();
  factory ReputationService() => _instance;
  ReputationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion);

  DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      _firestore.collection(FirestoreCollections.reputation).doc(uid);

  Future<UserReputation> getReputation(String uid) async {
    final doc = await _docRef(uid).get();
    if (!doc.exists) return UserReputation.empty(uid);
    return UserReputation.fromFirestore(doc);
  }

  /// Batched form of [getReputation] for a list of authors.
  ///
  /// The announcements feed needs a tier per author; fetching those one document
  /// at a time cost one round trip per author. `whereIn` on the document id
  /// collapses that into ceil(n/30) queries. Missing docs come back as
  /// [UserReputation.empty] so callers can treat the map as total.
  Future<Map<String, UserReputation>> getReputations(Iterable<String> uids) async {
    final unique = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return {};

    final results = <String, UserReputation>{};
    // Firestore caps whereIn at 30 values per query.
    const chunkSize = 30;
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < unique.length; i += chunkSize) {
      final chunk = unique.sublist(
          i, i + chunkSize > unique.length ? unique.length : i + chunkSize);
      futures.add(_firestore
          .collection(FirestoreCollections.reputation)
          .where(FieldPath.documentId, whereIn: chunk)
          .get());
    }

    for (final snap in await Future.wait(futures)) {
      for (final doc in snap.docs) {
        results[doc.id] = UserReputation.fromFirestore(doc);
      }
    }
    // Authors with no reputation document yet still need an entry.
    for (final uid in unique) {
      results.putIfAbsent(uid, () => UserReputation.empty(uid));
    }
    return results;
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
    await _functions.httpsCallable('addReputationEvent').call({
      'targetUid': uid,
      'type': type,
      'points': points,
      'description': description,
      'announcementId': announcementId,
    });
  }

  Future<void> touchActivity(String uid) async {
    await _functions.httpsCallable('touchReputationActivity').call({
      'targetUid': uid,
    });
  }
}
