import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../../models/user_profile.dart';
import '../core/account_scoped_cache.dart';
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

  final AccountScopedCache<UserProfile> _cache =
      AccountScopedCache<UserProfile>();

  /// Last-known profile. Empty until [load] completes or for guests.
  UserProfile get cached => _cache.read(_auth.userDocId) ?? UserProfile.empty;
  bool get isLoaded => _cache.contains(_auth.userDocId);

  DocumentReference<Map<String, dynamic>> _docRef(String uid) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.profile)
        .doc(FirestoreCollections.data);
  }

  /// Loads the profile from Firestore into [cached]. Safe to call at startup;
  /// idempotent unless [force].
  Future<UserProfile> load({bool force = false}) async {
    final uid = _auth.userDocId;
    if (uid == null) return UserProfile.empty;
    final cached = _cache.read(uid);
    if (cached != null && !force) return cached;

    final ref = _docRef(uid);
    late final UserProfile profile;
    try {
      final snap = await ref.get();
      profile = snap.exists && snap.data() != null
          ? UserProfile.fromMap(snap.data()!)
          : UserProfile.empty;
    } catch (e) {
      SecureLogger.error('PROFILE', 'Failed to load profile', e);
      profile = UserProfile.empty;
    }
    _cache.write(uid, profile);
    notifyListeners();
    return profile;
  }

  void invalidateCache() {
    _cache.clear();
    notifyListeners();
  }

  /// Persists [profile] and updates the cache. Returns false when signed out
  /// or the write fails.
  Future<bool> save(UserProfile profile) async {
    final uid = _auth.userDocId;
    if (uid == null) return false;
    final ref = _docRef(uid);
    try {
      await ref.set({
        ...profile.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cache.write(uid, profile);
      notifyListeners();
      return true;
    } catch (e) {
      SecureLogger.error('PROFILE', 'Failed to save profile', e);
      return false;
    }
  }
}
