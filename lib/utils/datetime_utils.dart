import 'package:cloud_firestore/cloud_firestore.dart';
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
