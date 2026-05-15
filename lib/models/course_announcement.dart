import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'announcement_source.dart';

class CourseAnnouncement {
  final String id;
  final String title;
  final String description;
  final String courseCode;
  final String sectionId;
  final DateTime eventDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String authorUid;
  final String authorName;
  final int upvotes;
  final int downvotes;
  final DateTime createdAt;

  final AnnouncementSource source;
  final String confidence;

  final String disputeState;
  final int totalFlagWeight;
  final String? topFlagReason;
  final String? topFlagCounterSource;
  final String? correctionText;
  final String? correctionSource;

  final String verificationState;
  final int confirmWeight;
  final int denyWeight;
  final int confirmCount;
  final int denyCount;

  const CourseAnnouncement({
    required this.id,
    required this.title,
    this.description = '',
    required this.courseCode,
    this.sectionId = '',
    required this.eventDate,
    this.startTime,
    this.endTime,
    required this.authorUid,
    required this.authorName,
    this.upvotes = 0,
    this.downvotes = 0,
    required this.createdAt,
    this.source = const AnnouncementSource(),
    this.confidence = 'fairly_sure',
    this.disputeState = 'undisputed',
    this.totalFlagWeight = 0,
    this.topFlagReason,
    this.topFlagCounterSource,
    this.correctionText,
    this.correctionSource,
    this.verificationState = 'unverified',
    this.confirmWeight = 0,
    this.denyWeight = 0,
    this.confirmCount = 0,
    this.denyCount = 0,
  });

  factory CourseAnnouncement.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CourseAnnouncement(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      courseCode: data['courseCode'] ?? '',
      sectionId: data['sectionId'] ?? '',
      eventDate: _parseTimestamp(data['eventDate']),
      startTime: _parseTimeOfDay(data['startTime']),
      endTime: _parseTimeOfDay(data['endTime']),
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? '',
      upvotes: data['upvotes'] ?? 0,
      downvotes: data['downvotes'] ?? 0,
      createdAt: _parseTimestamp(data['createdAt']),
      source:
          AnnouncementSource.fromMap(data['source'] as Map<String, dynamic>?),
      confidence: data['confidence'] ?? 'fairly_sure',
      disputeState: data['disputeState'] ?? 'undisputed',
      totalFlagWeight: data['totalFlagWeight'] ?? 0,
      topFlagReason: data['topFlagReason'],
      topFlagCounterSource: data['topFlagCounterSource'],
      correctionText: data['correctionText'],
      correctionSource: data['correctionSource'],
      verificationState: data['verificationState'] ?? 'unverified',
      confirmWeight: data['confirmWeight'] ?? 0,
      denyWeight: data['denyWeight'] ?? 0,
      confirmCount: data['confirmCount'] ?? 0,
      denyCount: data['denyCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'courseCode': courseCode,
      'sectionId': sectionId,
      'eventDate': Timestamp.fromDate(eventDate),
      'startTime': startTime != null
          ? {'hour': startTime!.hour, 'minute': startTime!.minute}
          : null,
      'endTime': endTime != null
          ? {'hour': endTime!.hour, 'minute': endTime!.minute}
          : null,
      'authorUid': authorUid,
      'authorName': authorName,
      'upvotes': upvotes,
      'downvotes': downvotes,
      'createdAt': FieldValue.serverTimestamp(),
      'source': source.toMap(),
      'confidence': confidence,
      'disputeState': disputeState,
      'totalFlagWeight': totalFlagWeight,
      'topFlagReason': topFlagReason,
      'topFlagCounterSource': topFlagCounterSource,
      'correctionText': correctionText,
      'correctionSource': correctionSource,
      'verificationState': verificationState,
      'confirmWeight': confirmWeight,
      'denyWeight': denyWeight,
      'confirmCount': confirmCount,
      'denyCount': denyCount,
    };
  }

  String get googleCalendarUrl {
    final details = description.isNotEmpty
        ? '$description\n\nCourse: $courseCode'
        : 'Course: $courseCode';
    final sectionInfo = sectionId.isNotEmpty ? ' ($sectionId)' : '';

    String dates;
    if (startTime != null) {
      final startDt = DateTime(eventDate.year, eventDate.month, eventDate.day,
          startTime!.hour, startTime!.minute);
      final endDt = endTime != null
          ? DateTime(eventDate.year, eventDate.month, eventDate.day,
              endTime!.hour, endTime!.minute)
          : startDt.add(const Duration(hours: 1));
      dates =
          '${_formatCalendarDateTime(startDt)}/${_formatCalendarDateTime(endDt)}';
    } else {
      final start = _formatCalendarDate(eventDate);
      final end = _formatCalendarDate(eventDate.add(const Duration(days: 1)));
      dates = '$start/$end';
    }

    return 'https://calendar.google.com/calendar/render'
        '?action=TEMPLATE'
        '&text=${Uri.encodeComponent('$title$sectionInfo')}'
        '&dates=$dates'
        '&details=${Uri.encodeComponent(details)}';
  }

  bool get isSectionSpecific => sectionId.isNotEmpty;
  bool get hasTime => startTime != null;
  bool get isDisputed => disputeState == 'disputed';
  bool get isCorrectionAccepted => disputeState == 'correction_accepted';
  bool get isStale =>
      verificationState == 'unverified' &&
      DateTime.now().difference(createdAt).inHours >= 4;
  int get netScore => upvotes - downvotes;

  static String _formatCalendarDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _formatCalendarDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y$m${d}T$h${min}00';
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  static TimeOfDay? _parseTimeOfDay(dynamic value) {
    if (value is Map) {
      final hour = value['hour'];
      final minute = value['minute'];
      if (hour is int && minute is int) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return null;
  }
}
