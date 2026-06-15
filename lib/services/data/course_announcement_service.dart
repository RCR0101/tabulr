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

  Stream<List<CourseAnnouncement>> watchAnnouncements(
      List<String> courseCodes) {
    if (courseCodes.isEmpty) return Stream.value([]);

    return _firestore
        .collection(FirestoreCollections.announcements)
        .where('courseCode', whereIn: courseCodes)
        .orderBy('eventDate', descending: true)
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

  Future<Map<String, AnnouncementUserState>> fetchUserStates(
      List<String> announcementIds) async {
    final uid = _authService.userDocId;
    if (uid == null || announcementIds.isEmpty) return {};

    final results = <String, AnnouncementUserState>{};
    final annRef = _firestore.collection(FirestoreCollections.announcements);

    final futures = announcementIds.map((id) async {
      final voteSnap =
          await annRef.doc(id).collection(FirestoreCollections.votes).doc(uid).get();
      final flagSnap =
          await annRef.doc(id).collection(FirestoreCollections.flags).doc(uid).get();
      final verifSnap =
          await annRef.doc(id).collection(FirestoreCollections.verifications).doc(uid).get();

      results[id] = AnnouncementUserState(
        vote: voteSnap.exists ? (voteSnap.data()?['vote'] as int?) : null,
        flag: flagSnap.exists ? AnnouncementFlag.fromFirestore(flagSnap) : null,
        verification: verifSnap.exists
            ? AnnouncementVerification.fromFirestore(verifSnap)
            : null,
      );
    });

    await Future.wait(futures);
    return results;
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
