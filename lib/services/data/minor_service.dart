import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/minor_programme.dart';
import '../ui/secure_logger.dart';

/// Reads and writes the `minors` collection.
///
/// The catalogue is small (about two dozen documents) and changes only when the
/// Bulletin is reissued, so it is fetched once and cached for the session
/// rather than streamed. Writes are admin-only, enforced in firestore.rules.
class MinorService {
  static final MinorService _instance = MinorService._internal();
  factory MinorService() => _instance;
  MinorService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<MinorProgramme>? _cache;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestoreCollections.minors);

  /// Drops the cache so the next read hits Firestore. Called after an admin
  /// edit so the student-facing list reflects it without a restart.
  void invalidateCache() => _cache = null;

  /// All minors, alphabetical. Returns an empty list rather than throwing so a
  /// fetch failure degrades to an empty state instead of breaking the screen.
  Future<List<MinorProgramme>> getMinors({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    try {
      final snap = await _col.orderBy('name').get();
      _cache = snap.docs.map(MinorProgramme.fromFirestore).toList();
      return _cache!;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to load minors', e);
      return _cache ?? const [];
    }
  }

  Future<bool> upsert(MinorProgramme minor) async {
    try {
      final data = {
        ...minor.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (minor.id.isEmpty) {
        await _col.add(data);
      } else {
        await _col.doc(minor.id).set(data, SetOptions(merge: true));
      }
      invalidateCache();
      return true;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to save minor', e);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _col.doc(id).delete();
      invalidateCache();
      return true;
    } catch (e) {
      SecureLogger.error('MINORS', 'Failed to delete minor', e);
      return false;
    }
  }
}
