import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a bug report, advanced by admins in the Bug Tracker.
enum BugStatus {
  pending('Pending', 'pending'),
  inReview('In Review', 'in_review'),
  devInProgress('Dev In Progress', 'dev_in_progress'),
  fixed('Fixed', 'fixed');

  /// Human-readable label shown in the UI.
  final String label;

  /// Stable value persisted in Firestore (never rename these).
  final String id;

  const BugStatus(this.label, this.id);

  static BugStatus fromId(String? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => pending);
}

/// Category → sub-category options shown on the report form. Kept intentionally
/// specific so reports are actionable. Edit here to adjust the taxonomy; the
/// stored strings are the labels themselves, so keep existing labels stable.
const Map<String, List<String>> bugReportTaxonomy = {
  'Timetable Builder': [
    'Generator results',
    'Section clashes',
    'Add / Swap courses',
    'Quick Replace',
    'Export / Share',
    'Saving / Sync',
    'Something else',
  ],
  'Courses & Data': [
    'Wrong course info',
    'Missing course',
    'Wrong professor',
    'Wrong section timing',
    'Wrong credits',
    'Duplicate course',
    'Something else',
  ],
  'CGPA Calculator': [
    'Wrong calculation',
    'Grade Planner',
    'CG Booster',
    'Performance sheet import',
    'Auto-load CDCs',
    'Something else',
  ],
  'Exam Seating': [
    'Wrong room',
    'Missing course',
    'ID range incorrect',
    'No data for exam',
    'Something else',
  ],
  'Acad Drives': [
    'Broken link',
    'Wrong / missing material',
    'Upload / submission issue',
    'Something else',
  ],
  'Calendar': [
    'Wrong semester dates',
    'Wrong exam dates',
    'Events incorrect',
    'Something else',
  ],
  'Professors': [
    'Wrong details',
    'Wrong ratings',
    'Missing professor',
    'Something else',
  ],
  'Course Guide & Electives': [
    'Wrong CDC list',
    'Wrong elective info',
    'Prerequisites incorrect',
    'Something else',
  ],
  'Account & Login': [
    'Cannot sign in',
    'Data not syncing',
    'Lost data',
    'Wrong campus',
    'Something else',
  ],
  'UI / Design': [
    'Visual glitch',
    'Theme / colors',
    'Layout / responsiveness',
    'Text / label error',
    'Something else',
  ],
  'Performance': [
    'Slow / laggy',
    'Crash',
    'Freeze / hang',
    'Something else',
  ],
  'Feature Request': [
    'New feature',
    'Improvement to existing',
    'Something else',
  ],
  'Other': [
    'General feedback',
    'Not listed here',
  ],
};

/// One message in a report's conversation thread.
///
/// Lives in `bug_reports/{reportId}/messages`. Who may post is enforced by
/// firestore.rules: admins, and the report's own author. [isAdmin] is validated
/// against the writer's real role there, so it can be trusted for display.
class BugMessage {
  final String id;
  final String authorUid;
  final String body;

  /// True when written by an admin; drives the "Tabulr Team" attribution.
  final bool isAdmin;
  final DateTime createdAt;

  const BugMessage({
    required this.id,
    required this.authorUid,
    required this.body,
    required this.isAdmin,
    required this.createdAt,
  });

  factory BugMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BugMessage(
      id: doc.id,
      authorUid: data['authorUid'] ?? '',
      body: data['body'] ?? '',
      isAdmin: data['isAdmin'] == true,
      // A just-written message has a null server timestamp until the write
      // lands; treating that as "now" keeps optimistic local echoes in order.
      createdAt: BugReport._parseTimestamp(data['createdAt']),
    );
  }
}

/// A single bug report filed by a user.
class BugReport {
  final String id;
  final String authorUid;
  final String authorEmail;
  final String category;
  final String subCategory;
  final String description;
  final BugStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Last time each side posted to the thread. Used to flag unread replies
  /// without paying for a read of the messages subcollection per list row.
  final DateTime? lastAdminReplyAt;
  final DateTime? lastUserReplyAt;

  const BugReport({
    required this.id,
    required this.authorUid,
    required this.authorEmail,
    required this.category,
    required this.subCategory,
    required this.description,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.lastAdminReplyAt,
    this.lastUserReplyAt,
  });

  factory BugReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BugReport(
      id: doc.id,
      authorUid: data['authorUid'] ?? '',
      authorEmail: data['authorEmail'] ?? '',
      category: data['category'] ?? '',
      subCategory: data['subCategory'] ?? '',
      description: data['description'] ?? '',
      status: BugStatus.fromId(data['status'] as String?),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt:
          data['updatedAt'] != null ? _parseTimestamp(data['updatedAt']) : null,
      lastAdminReplyAt: data['lastAdminReplyAt'] != null
          ? _parseTimestamp(data['lastAdminReplyAt'])
          : null,
      lastUserReplyAt: data['lastUserReplyAt'] != null
          ? _parseTimestamp(data['lastUserReplyAt'])
          : null,
    );
  }

  /// Whether the other side replied after this side last did — a cheap
  /// "needs your attention" signal derived from the two stamps alone.
  bool get hasUnreadForUser =>
      lastAdminReplyAt != null &&
      (lastUserReplyAt == null || lastAdminReplyAt!.isAfter(lastUserReplyAt!));

  bool get hasUnreadForAdmin =>
      lastUserReplyAt != null &&
      (lastAdminReplyAt == null || lastUserReplyAt!.isAfter(lastAdminReplyAt!));

  /// Payload for a brand-new report. `createdAt` uses the server clock so
  /// ordering is authoritative regardless of device time.
  Map<String, dynamic> toCreateMap() => {
        'authorUid': authorUid,
        'authorEmail': authorEmail,
        'category': category,
        'subCategory': subCategory,
        'description': description,
        'status': BugStatus.pending.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
