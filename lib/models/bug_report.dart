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
    );
  }

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
