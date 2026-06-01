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
