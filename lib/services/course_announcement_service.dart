import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/announcement_flag.dart';
import '../models/announcement_source.dart';
import '../models/announcement_verification.dart';
import '../models/course_announcement.dart';
import 'auth_service.dart';
import 'reputation_service.dart';
import 'secure_logger.dart';

class CourseAnnouncementService {
  static final CourseAnnouncementService _instance =
      CourseAnnouncementService._internal();
  factory CourseAnnouncementService() => _instance;
  CourseAnnouncementService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final ReputationService _reputationService = ReputationService();

  static const String _collection = 'announcements';

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
        .collection(_collection)
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

    final docRef = _firestore.collection(_collection).doc();
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
    final docRef = _firestore.collection(_collection).doc(id);
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

    final flagsSnap = await docRef.collection('flags').get();
    final verifSnap = await docRef.collection('verifications').get();
    final votesSnap = await docRef.collection('votes').get();
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

  // --- Voting ---

  Future<void> toggleVote(String announcementId, int voteValue) async {
    assert(voteValue == 1 || voteValue == -1);
    final uid = _authService.userDocId;
    if (uid == null) return;

    final announcementRef =
        _firestore.collection(_collection).doc(announcementId);
    final voteRef = announcementRef.collection('votes').doc(uid);

    await _firestore.runTransaction((transaction) async {
      final voteSnap = await transaction.get(voteRef);
      final announcementSnap = await transaction.get(announcementRef);
      if (!announcementSnap.exists) return;

      final existingVote =
          voteSnap.exists ? (voteSnap.data()?['vote'] as int?) : null;

      int upDelta = 0;
      int downDelta = 0;

      if (existingVote == null) {
        if (voteValue == 1) {
          upDelta = 1;
        } else {
          downDelta = 1;
        }
        transaction.set(voteRef, {'vote': voteValue});
      } else if (existingVote == voteValue) {
        if (voteValue == 1) {
          upDelta = -1;
        } else {
          downDelta = -1;
        }
        transaction.delete(voteRef);
      } else {
        if (voteValue == 1) {
          upDelta = 1;
          downDelta = -1;
        } else {
          upDelta = -1;
          downDelta = 1;
        }
        transaction.set(voteRef, {'vote': voteValue});
      }

      transaction.update(announcementRef, {
        'upvotes': FieldValue.increment(upDelta),
        'downvotes': FieldValue.increment(downDelta),
      });
    });
  }

  Stream<int?> watchUserVote(String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection(_collection)
        .doc(announcementId)
        .collection('votes')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? (snap.data()?['vote'] as int?) : null);
  }

  // --- Flagging (System 3) ---

  Future<void> submitFlag({
    required String announcementId,
    required String reason,
    String? counterSourceUrl,
    required String confidence,
  }) async {
    final uid = _authService.userDocId;
    if (uid == null) return;

    final rep = await _reputationService.getReputation(uid);
    if (rep.isSuspended) return;

    final announcementRef =
        _firestore.collection(_collection).doc(announcementId);
    final flagRef = announcementRef.collection('flags').doc(uid);

    await _firestore.runTransaction((tx) async {
      final existingFlag = await tx.get(flagRef);
      if (existingFlag.exists) return;

      final announcementSnap = await tx.get(announcementRef);
      if (!announcementSnap.exists) return;
      final announcement = CourseAnnouncement.fromFirestore(announcementSnap);

      final weight = rep.flagWeight;
      final flag = AnnouncementFlag(
        uid: uid,
        reason: reason,
        counterSourceUrl: counterSourceUrl,
        confidence: confidence,
        weight: weight,
        timestamp: DateTime.now(),
      );

      tx.set(flagRef, flag.toFirestore());

      final newFlagWeight = announcement.totalFlagWeight + weight;
      final quorum = announcement.source.disputeQuorum;

      final updates = <String, dynamic>{
        'totalFlagWeight': FieldValue.increment(weight),
      };

      if (announcement.topFlagReason == null ||
          weight > (announcement.totalFlagWeight ~/ 2)) {
        updates['topFlagReason'] = reason;
        if (counterSourceUrl != null) {
          updates['topFlagCounterSource'] = counterSourceUrl;
        }
      }

      if (newFlagWeight >= quorum &&
          announcement.disputeState == 'undisputed') {
        updates['disputeState'] = 'disputed';
      }

      tx.update(announcementRef, updates);
    });

    final snap = await announcementRef.get();
    if (snap.exists && snap.data()?['disputeState'] == 'disputed') {
      final authorUid = snap.data()?['authorUid'] as String?;
      if (authorUid != null) {
        await _reputationService.addEvent(
          uid: authorUid,
          type: 'post_disputed',
          points: -4,
          description: 'Post flagged as incorrect by community',
          announcementId: announcementId,
        );
      }
    }

    await _reputationService.touchActivity(uid);
  }

  Stream<List<AnnouncementFlag>> watchFlags(String announcementId) {
    return _firestore
        .collection(_collection)
        .doc(announcementId)
        .collection('flags')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AnnouncementFlag.fromFirestore(d)).toList());
  }

  Stream<AnnouncementFlag?> watchUserFlag(String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection(_collection)
        .doc(announcementId)
        .collection('flags')
        .doc(uid)
        .snapshots()
        .map((snap) =>
            snap.exists ? AnnouncementFlag.fromFirestore(snap) : null);
  }

  Future<void> acceptCorrection({
    required String announcementId,
    required String correctionText,
    String? correctionSource,
  }) async {
    final uid = _authService.userDocId;
    if (uid == null) return;

    final ref = _firestore.collection(_collection).doc(announcementId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    if (data['authorUid'] != uid) return;

    final conf = data['confidence'] as String? ?? 'fairly_sure';
    final penalty = conf == 'certain' ? -12 : -8;

    await ref.update({
      'disputeState': 'correction_accepted',
      'correctionText': correctionText,
      'correctionSource': correctionSource,
    });

    await _reputationService.addEvent(
      uid: uid,
      type: 'correction_accepted',
      points: penalty,
      description: 'Accepted correction on own post',
      announcementId: announcementId,
    );

    final flagsSnap = await ref.collection('flags').get();
    if (flagsSnap.docs.isNotEmpty) {
      final firstFlag = flagsSnap.docs.first;
      final flaggerUid = firstFlag.id;
      final hasCounterSource =
          firstFlag.data()['counterSourceUrl'] != null;
      await _reputationService.addEvent(
        uid: flaggerUid,
        type: 'correct_flag',
        points: hasCounterSource ? 14 : 8,
        description: hasCounterSource
            ? 'First correct flag with counter-source'
            : 'First correct flag on incorrect post',
        announcementId: announcementId,
      );
    }
  }

  // --- Verification (System 5) ---

  Future<void> submitVerification({
    required String announcementId,
    required VerificationType type,
    String? note,
  }) async {
    final uid = _authService.userDocId;
    if (uid == null) return;

    final rep = await _reputationService.getReputation(uid);
    if (rep.isSuspended) return;

    final announcementRef =
        _firestore.collection(_collection).doc(announcementId);
    final verifRef = announcementRef.collection('verifications').doc(uid);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(verifRef);
      final announcementSnap = await tx.get(announcementRef);
      if (!announcementSnap.exists) return;

      final weight = rep.flagWeight;
      final isConfirm = type == VerificationType.confirm;

      if (existing.exists) {
        final oldType = existing.data()?['type'] as String?;
        final oldWeight = existing.data()?['weight'] as int? ?? 1;
        final wasConfirm = oldType == 'confirm';

        if (wasConfirm == isConfirm) return;

        tx.update(announcementRef, {
          'confirmWeight':
              FieldValue.increment(isConfirm ? weight : -oldWeight),
          'denyWeight':
              FieldValue.increment(isConfirm ? -oldWeight : weight),
          'confirmCount': FieldValue.increment(isConfirm ? 1 : -1),
          'denyCount': FieldValue.increment(isConfirm ? -1 : 1),
        });
      } else {
        tx.update(announcementRef, {
          if (isConfirm) 'confirmWeight': FieldValue.increment(weight),
          if (!isConfirm) 'denyWeight': FieldValue.increment(weight),
          if (isConfirm) 'confirmCount': FieldValue.increment(1),
          if (!isConfirm) 'denyCount': FieldValue.increment(1),
        });
      }

      final verification = AnnouncementVerification(
        uid: uid,
        type: type,
        note: note,
        weight: weight,
        timestamp: DateTime.now(),
      );
      tx.set(verifRef, verification.toFirestore());
    });

    await _updateVerificationState(announcementId);

    if (!isConfirm(type)) {
      final snap = await announcementRef.get();
      if (snap.exists) {
        final dw = snap.data()?['denyWeight'] as int? ?? 0;
        final quorum = AnnouncementSource.fromMap(
                snap.data()?['source'] as Map<String, dynamic>?)
            .disputeQuorum;
        final currentFlagWeight =
            snap.data()?['totalFlagWeight'] as int? ?? 0;
        final denyContribution = (dw * 0.5).round();
        if (currentFlagWeight + denyContribution >= quorum &&
            snap.data()?['disputeState'] == 'undisputed') {
          await announcementRef.update({'disputeState': 'disputed'});
        }
      }
    }

    await _reputationService.touchActivity(uid);
  }

  bool isConfirm(VerificationType type) => type == VerificationType.confirm;

  Future<void> _updateVerificationState(String announcementId) async {
    final ref = _firestore.collection(_collection).doc(announcementId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final cw = snap.data()?['confirmWeight'] as int? ?? 0;
    final dw = snap.data()?['denyWeight'] as int? ?? 0;
    final total = cw + dw;

    String newState;
    if (total == 0) {
      newState = 'unverified';
    } else if (dw > 0 && dw >= cw * 2) {
      newState = 'likely_incorrect';
    } else if (dw > 0 && total > 0 && dw >= total * 0.25) {
      newState = 'contested';
    } else if (cw >= 3 && (total == 0 || dw < total * 0.25)) {
      newState = 'community_verified';
    } else {
      newState = 'partially_verified';
    }

    final oldState = snap.data()?['verificationState'] as String? ?? 'unverified';
    if (newState == oldState) return;

    await ref.update({'verificationState': newState});

    final authorUid = snap.data()?['authorUid'] as String?;
    if (authorUid == null) return;

    if (newState == 'community_verified' && oldState != 'community_verified') {
      await _reputationService.addEvent(
        uid: authorUid,
        type: 'post_community_verified',
        points: 10,
        description: 'Post reached community verified status',
        announcementId: announcementId,
      );
      final verifs =
          await ref.collection('verifications').get();
      for (final v in verifs.docs) {
        if (v.data()['type'] == 'confirm') {
          await _reputationService.addEvent(
            uid: v.id,
            type: 'confirmed_verified_post',
            points: 1,
            description: 'Confirmed a post that reached community verified',
            announcementId: announcementId,
          );
        }
      }
    }

    if (newState == 'likely_incorrect' &&
        oldState != 'likely_incorrect') {
      final verifs =
          await ref.collection('verifications').get();
      for (final v in verifs.docs) {
        if (v.data()['type'] == 'deny') {
          await _reputationService.addEvent(
            uid: v.id,
            type: 'denied_incorrect_post',
            points: 2,
            description: 'Denied a post later found likely incorrect',
            announcementId: announcementId,
          );
        } else if (v.data()['type'] == 'confirm') {
          await _reputationService.addEvent(
            uid: v.id,
            type: 'confirmed_incorrect_post',
            points: -3,
            description: 'Confirmed a post later found likely incorrect',
            announcementId: announcementId,
          );
        }
      }
    }
  }

  Stream<AnnouncementVerification?> watchUserVerification(
      String announcementId) {
    final uid = _authService.userDocId;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection(_collection)
        .doc(announcementId)
        .collection('verifications')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists
            ? AnnouncementVerification.fromFirestore(snap)
            : null);
  }
}
