import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../../models/user_profile.dart';
import '../ui/secure_logger.dart';
import 'auth_service.dart';

/// Stores a user's reusable defaults (ID, branches, semester) at
/// `users/{uid}/profile/data`. Owner-only access is already covered by the
/// existing `users/{userId}/{sub=**}` Firestore rule, so no new rules are
/// needed.
///
/// The profile is loaded once at startup and cached in memory so consumers
/// (exam seating, CDC loader, …) can read defaults synchronously via [cached].
class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  UserProfile _cached = UserProfile.empty;
  bool _loaded = false;

  /// Last-known profile. Empty until [load] completes or for guests.
  UserProfile get cached => _cached;
  bool get isLoaded => _loaded;

  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = _auth.userDocId;
    if (uid == null) return null;
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.profile)
        .doc(FirestoreCollections.data);
  }

  /// Loads the profile from Firestore into [cached]. Safe to call at startup;
  /// idempotent unless [force].
  Future<UserProfile> load({bool force = false}) async {
    if (_loaded && !force) return _cached;
    final ref = _docRef();
    if (ref == null) {
      _cached = UserProfile.empty;
      _loaded = true;
      return _cached;
    }
    try {
      final snap = await ref.get();
      _cached = snap.exists && snap.data() != null
          ? UserProfile.fromMap(snap.data()!)
          : UserProfile.empty;
    } catch (e) {
      SecureLogger.error('PROFILE', 'Failed to load profile', e);
      _cached = UserProfile.empty;
    }
    _loaded = true;
    notifyListeners();
    return _cached;
  }

  /// Persists [profile] and updates the cache. Returns false when signed out
  /// or the write fails.
  Future<bool> save(UserProfile profile) async {
    final ref = _docRef();
    if (ref == null) return false;
    try {
      await ref.set({
        ...profile.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cached = profile;
      _loaded = true;
      notifyListeners();
      return true;
    } catch (e) {
      SecureLogger.error('PROFILE', 'Failed to save profile', e);
      return false;
    }
  }
}
