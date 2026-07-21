import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../../models/announcement_flag.dart';
import '../../models/announcement_source.dart';
import '../../models/announcement_user_state.dart';
import '../../models/announcement_verification.dart';
import '../../models/course_announcement.dart';
import 'auth_service.dart';
import 'reputation_service.dart';
import '../ui/secure_logger.dart';
import '../../constants/app_constants.dart';

class CourseAnnouncementService {
  static final CourseAnnouncementService _instance =
      CourseAnnouncementService._internal();
  factory CourseAnnouncementService() => _instance;
  CourseAnnouncementService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final ReputationService _reputationService = ReputationService();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion);

  static const _testUsers = String.fromEnvironment('TEST_USERS');

  bool isHyderabadUser() {
    final email = _authService.userEmail;
    if (email == null) return false;
    if (email.endsWith('@hyderabad.bits-pilani.ac.in')) return true;
    if (_testUsers.isNotEmpty) {
      return _testUsers.split(',').contains(email);
    }
    return false;
  }

  // --- Announcements CRUD ---

  /// How far back the feed looks. Announcements are semester-scoped events
  /// (quizzes, deadlines), so anything older is noise — and without a bound the
  /// listener downloads every historical announcement for the user's courses on
  /// every subscribe, forever.
  static const Duration announcementRetention = Duration(days: 120);

  /// Safety cap so one very busy course can't produce an unbounded snapshot.
  /// Combined with the descending sort this keeps the newest entries.
  static const int announcementFetchLimit = 200;

  Stream<List<CourseAnnouncement>> watchAnnouncements(
      List<String> courseCodes) {
    if (courseCodes.isEmpty) return Stream.value([]);

    final cutoff = DateTime.now().subtract(announcementRetention);

    // The range filter is on the same field as the orderBy, so this is served
    // by the existing (courseCode ASC, eventDate DESC) composite index.
    return _firestore
        .collection(FirestoreCollections.announcements)
        .where('courseCode', whereIn: courseCodes)
        .where('eventDate', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('eventDate', descending: true)
        .limit(announcementFetchLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CourseAnnouncement.fromFirestore(doc))
            .toList());
  }

  Future<void> postAnnouncement({
    required String title,
    String description = '',
    required String courseCode,
    String sectionId = '',
    required DateTime eventDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    AnnouncementSource source = const AnnouncementSource(),
    String confidence = 'fairly_sure',
  }) async {
    final user = _authService.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final docRef = _firestore.collection(FirestoreCollections.announcements).doc();
    final announcement = CourseAnnouncement(
      id: docRef.id,
      title: title,
      description: description,
      courseCode: courseCode,
      sectionId: sectionId,
      eventDate: eventDate,
      startTime: startTime,
      endTime: endTime,
      authorUid: _authService.userDocId!,
      authorName: user.displayName ?? 'Anonymous',
      createdAt: DateTime.now(),
      source: source,
      confidence: confidence,
    );

    await docRef.set(announcement.toFirestore());

    if (source.isHighOrMedium) {
      await _reputationService.addEvent(
        uid: _authService.userDocId!,
        type: 'source_attached',
        points: 2,
        description: 'Attached ${source.label} to announcement',
        announcementId: docRef.id,
      );
    }

    await _reputationService.touchActivity(_authService.userDocId!);
    SecureLogger.info('ANNOUNCEMENTS', 'Posted announcement: $title');
  }

  Future<void> deleteAnnouncement(String id) async {
    final docRef = _firestore.collection(FirestoreCollections.announcements).doc(id);
    final snap = await docRef.get();

    if (snap.exists) {
      final data = snap.data()!;
      final authorUid = data['authorUid'] as String?;
      final state = data['disputeState'] as String? ?? 'undisputed';

      if (authorUid != null &&
          (state == 'disputed' || state == 'correction_accepted')) {
        await _reputationService.addEvent(
          uid: authorUid,
          type: 'post_removed_inaccuracy',
          points: -15,
          description: 'Post removed while in $state state',
          announcementId: id,
        );
      }
    }

    final flagsSnap = await docRef.collection(FirestoreCollections.flags).get();
    final verifSnap = await docRef.collection(FirestoreCollections.verifications).get();
    final votesSnap = await docRef.collection(FirestoreCollections.votes).get();
    final batch = _firestore.batch();
    for (final d in flagsSnap.docs) {
      batch.delete(d.reference);
    }
    for (final d in verifSnap.docs) {
      batch.delete(d.reference);
    }
    for (final d in votesSnap.docs) {
      batch.delete(d.reference);
    }
    batch.delete(docRef);
    await batch.commit();
    SecureLogger.info('ANNOUNCEMENTS', 'Deleted announcement: $id');
  }

  // --- Voting (via Cloud Function) ---

  Future<void> toggleVote(String announcementId, int voteValue) async {
    assert(voteValue == 1 || voteValue == -1);
    await _functions.httpsCallable('toggleVote').call({
      'announcementId': announcementId,
      'voteValue': voteValue,
    });
  }

  /// Fetches the caller's own vote/flag/verification for [announcementIds].
  ///
  /// Uses three collection-group queries scoped to this user rather than three
  /// point reads *per announcement* — the old shape cost 3xN reads and scaled
  /// with the number of announcements on screen. These queries return only the
  /// documents this user actually created (usually a handful), so cost tracks
  /// the user's own activity instead of the size of the feed.
  Future<Map<String, AnnouncementUserState>> fetchUserStates(
      List<String> announcementIds) async {
    final uid = _authService.userDocId;
    if (uid == null || announcementIds.isEmpty) return {};

    final wanted = announcementIds.toSet();

    // The announcement id is the parent of the {votes,flags,verifications} doc.
    String? announcementIdOf(DocumentSnapshot<Map<String, dynamic>> doc) =>
        doc.reference.parent.parent?.id;

    Future<QuerySnapshot<Map<String, dynamic>>> mine(String group) =>
        _firestore.collectionGroup(group).where('uid', isEqualTo: uid).get();

    final snaps = await Future.wait([
      mine(FirestoreCollections.votes),
      mine(FirestoreCollections.flags),
      mine(FirestoreCollections.verifications),
    ]);

    final votes = <String, int?>{};
    for (final doc in snaps[0].docs) {
      final id = announcementIdOf(doc);
      if (id != null && wanted.contains(id)) votes[id] = doc.data()['vote'] as int?;
    }

    final flags = <String, AnnouncementFlag>{};
    for (final doc in snaps[1].docs) {
      final id = announcementIdOf(doc);
      if (id != null && wanted.contains(id)) {
        flags[id] = AnnouncementFlag.fromFirestore(doc);
      }
    }

    final verifications = <String, AnnouncementVerification>{};
    for (final doc in snaps[2].docs) {
      final id = announcementIdOf(doc);
      if (id != null && wanted.contains(id)) {
        verifications[id] = AnnouncementVerification.fromFirestore(doc);
      }
    }

    // Every requested id gets an entry so callers can cache "no state" and
    // avoid re-querying (the screen keys its cache on presence).
    return {
      for (final id in wanted)
        id: AnnouncementUserState(
          vote: votes[id],
          flag: flags[id],
          verification: verifications[id],
        ),
    };
  }

  Stream<int?> watchUserVote(String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection(FirestoreCollections.announcements)
        .doc(announcementId)
        .collection(FirestoreCollections.votes)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? (snap.data()?['vote'] as int?) : null);
  }

  // --- Flagging (via Cloud Function) ---

  Future<void> submitFlag({
    required String announcementId,
    required String reason,
    String? counterSourceUrl,
    required String confidence,
  }) async {
    await _functions.httpsCallable('submitFlag').call({
      'announcementId': announcementId,
      'reason': reason,
      'counterSourceUrl': counterSourceUrl,
      'confidence': confidence,
    });
  }

  Stream<List<AnnouncementFlag>> watchFlags(String announcementId) {
    return _firestore
        .collection(FirestoreCollections.announcements)
        .doc(announcementId)
        .collection(FirestoreCollections.flags)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AnnouncementFlag.fromFirestore(d)).toList());
  }

  Stream<AnnouncementFlag?> watchUserFlag(String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection(FirestoreCollections.announcements)
        .doc(announcementId)
        .collection(FirestoreCollections.flags)
        .doc(uid)
        .snapshots()
        .map((snap) =>
            snap.exists ? AnnouncementFlag.fromFirestore(snap) : null);
  }

  // --- Accept Correction (via Cloud Function) ---

  Future<void> acceptCorrection({
    required String announcementId,
    required String correctionText,
    String? correctionSource,
  }) async {
    await _functions.httpsCallable('acceptCorrection').call({
      'announcementId': announcementId,
      'correctionText': correctionText,
      'correctionSource': correctionSource,
    });
  }

  // --- Verification (via Cloud Function) ---

  Future<void> submitVerification({
    required String announcementId,
    required VerificationType type,
    String? note,
  }) async {
    await _functions.httpsCallable('submitVerification').call({
      'announcementId': announcementId,
      'type': type == VerificationType.confirm ? 'confirm' : 'deny',
      'note': note,
    });
  }

  Stream<AnnouncementVerification?> watchUserVerification(
      String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection(FirestoreCollections.announcements)
        .doc(announcementId)
        .collection(FirestoreCollections.verifications)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists
            ? AnnouncementVerification.fromFirestore(snap)
            : null);
  }
}
