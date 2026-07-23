import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';
import '../models/course.dart';

DateTime parseDateTime(dynamic value) {
  if (value == null) {
    return DateTime.now();
  } else if (value is Timestamp) {
    return value.toDate();
  } else if (value is String) {
    return DateTime.parse(value);
  } else if (value is Map && value['_seconds'] != null) {
    final seconds = value['_seconds'];
    final nanoseconds = value['_nanoseconds'] ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + (nanoseconds ~/ 1000000));
  } else {
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      return DateTime.now();
    }
  }
}

String getDayName(DayOfWeek day, {bool abbreviated = false}) {
  switch (day) {
    case DayOfWeek.M: return abbreviated ? 'Mon' : 'Monday';
    case DayOfWeek.T: return abbreviated ? 'Tue' : 'Tuesday';
    case DayOfWeek.W: return abbreviated ? 'Wed' : 'Wednesday';
    case DayOfWeek.Th: return abbreviated ? 'Thu' : 'Thursday';
    case DayOfWeek.F: return abbreviated ? 'Fri' : 'Friday';
    case DayOfWeek.S: return abbreviated ? 'Sat' : 'Saturday';
  }
}

/// Abbreviated month, e.g. "Mar". [DayConstants.monthNames] is 1-indexed
/// (index 0 is a placeholder), so the month number is used directly.
String monthAbbrev(int month) => DayConstants.monthNames[month];

/// "12 Mar".
String formatDayMonth(DateTime d) => '${d.day} ${monthAbbrev(d.month)}';

/// "12 Mar 2026".
String formatDayMonthYear(DateTime d) => '${formatDayMonth(d)} ${d.year}';

/// Relative for the last week ("just now", "5m ago", "3d ago"), an absolute
/// date beyond that. Shared by the bug reporter and announcement lists.
String formatRelativeDate(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDayMonthYear(d);
}
