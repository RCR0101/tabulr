import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/bug_report.dart';
import '../ui/secure_logger.dart';
import 'auth_service.dart';

/// Reads and writes bug reports in the top-level `bug_reports` collection.
///
/// Access is enforced by firestore.rules: a user may create reports authored by
/// themselves and read their own; admins may read everything and update status.
class BugReportService {
  static final BugReportService _instance = BugReportService._internal();
  factory BugReportService() => _instance;
  BugReportService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  /// Upper bound on how many reports a stream fetches. Bug volume is low for a
  /// single app, so a capped, client-paginated list keeps the UI simple while
  /// staying well within a single query.
  static const int maxFetch = 300;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestoreCollections.bugReports);

  /// Files a new report authored by the current user. Returns false if the
  /// user isn't signed in or the write fails.
  Future<bool> submitReport({
    required String category,
    required String subCategory,
    required String description,
  }) async {
    final uid = _auth.userDocId;
    final email = _auth.userEmail;
    if (uid == null || email == null) return false;

    try {
      final report = BugReport(
        id: '',
        authorUid: uid,
        authorEmail: email,
        category: category,
        subCategory: subCategory,
        description: description.trim(),
        status: BugStatus.pending,
        createdAt: DateTime.now(),
      );
      await _col.add(report.toCreateMap());
      return true;
    } catch (e) {
      SecureLogger.error('BUG_REPORT', 'Failed to submit report', e);
      return false;
    }
  }

  /// Live stream of the signed-in user's own reports, newest first. Emits an
  /// empty list when signed out.
  Stream<List<BugReport>> myReports() {
    final uid = _auth.userDocId;
    if (uid == null) return Stream.value(const []);
    return _col
        .where('authorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(maxFetch)
        .snapshots()
        .map((snap) => snap.docs.map(BugReport.fromFirestore).toList());
  }

  /// Live stream of every report (admin only), newest first.
  Stream<List<BugReport>> allReports() {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(maxFetch)
        .snapshots()
        .map((snap) => snap.docs.map(BugReport.fromFirestore).toList());
  }

  /// Live stream of a report's conversation, oldest first so it reads top-down.
  ///
  /// Readable by the report's author and by admins (enforced in
  /// firestore.rules); anyone else gets a permission error from the stream.
  Stream<List<BugMessage>> messages(String reportId) {
    return _col
        .doc(reportId)
        .collection(FirestoreCollections.bugReportMessages)
        .orderBy('createdAt')
        .limit(maxFetch)
        .snapshots()
        .map((snap) => snap.docs.map(BugMessage.fromFirestore).toList());
  }

  /// Posts a reply to a report's thread.
  ///
  /// [asAdmin] must reflect the sender's real role — firestore.rules rejects
  /// the write if it doesn't, so a user cannot post as the team. Also stamps
  /// the matching `last*ReplyAt` on the parent so the other side sees an unread
  /// marker without reading the whole thread.
  Future<bool> sendMessage({
    required String reportId,
    required String body,
    required bool asAdmin,
  }) async {
    final uid = _auth.userDocId;
    final trimmed = body.trim();
    if (uid == null || trimmed.isEmpty) return false;

    try {
      await _col
          .doc(reportId)
          .collection(FirestoreCollections.bugReportMessages)
          .add({
        'authorUid': uid,
        'body': trimmed,
        'isAdmin': asAdmin,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Best-effort: the reply itself is already saved, so a failure here costs
      // an unread badge, not the message.
      try {
        await _col.doc(reportId).update({
          if (asAdmin)
            'lastAdminReplyAt': FieldValue.serverTimestamp()
          else
            'lastUserReplyAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        SecureLogger.warning(
            'BUG_REPORT', 'Failed to stamp reply time', {'error': e.toString()});
      }
      return true;
    } catch (e) {
      SecureLogger.error('BUG_REPORT', 'Failed to send message', e);
      return false;
    }
  }

  /// Advances a report's status (admin only). Returns false on failure.
  Future<bool> updateStatus(String reportId, BugStatus status) async {
    try {
      await _col.doc(reportId).update({
        'status': status.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      SecureLogger.error('BUG_REPORT', 'Failed to update status', e);
      return false;
    }
  }
}
