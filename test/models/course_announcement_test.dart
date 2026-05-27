import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course_announcement.dart';

CourseAnnouncement _makeAnnouncement({
  String disputeState = 'undisputed',
  String verificationState = 'unverified',
  int upvotes = 0,
  int downvotes = 0,
  String sectionId = '',
  TimeOfDay? startTime,
  TimeOfDay? endTime,
  DateTime? createdAt,
  DateTime? eventDate,
  String description = '',
}) {
  return CourseAnnouncement(
    id: 'ann-1',
    title: 'Test Announcement',
    description: description,
    courseCode: 'CS F111',
    sectionId: sectionId,
    eventDate: eventDate ?? DateTime(2026, 3, 15),
    startTime: startTime,
    endTime: endTime,
    authorUid: 'user-1',
    authorName: 'Test User',
    upvotes: upvotes,
    downvotes: downvotes,
    createdAt: createdAt ?? DateTime.now(),
    disputeState: disputeState,
    verificationState: verificationState,
  );
}

void main() {
  group('pure getters', () {
    test('netScore = upvotes - downvotes', () {
      final ann = _makeAnnouncement(upvotes: 10, downvotes: 3);
      expect(ann.netScore, 7);
    });

    test('netScore can be negative', () {
      final ann = _makeAnnouncement(upvotes: 2, downvotes: 8);
      expect(ann.netScore, -6);
    });

    test('isDisputed when disputeState is disputed', () {
      expect(_makeAnnouncement(disputeState: 'disputed').isDisputed, isTrue);
      expect(_makeAnnouncement(disputeState: 'undisputed').isDisputed, isFalse);
    });

    test('isCorrectionAccepted', () {
      expect(
        _makeAnnouncement(disputeState: 'correction_accepted').isCorrectionAccepted,
        isTrue,
      );
      expect(
        _makeAnnouncement(disputeState: 'undisputed').isCorrectionAccepted,
        isFalse,
      );
    });

    test('isSectionSpecific', () {
      expect(_makeAnnouncement(sectionId: 'L1').isSectionSpecific, isTrue);
      expect(_makeAnnouncement(sectionId: '').isSectionSpecific, isFalse);
    });

    test('hasTime', () {
      expect(
        _makeAnnouncement(startTime: const TimeOfDay(hour: 9, minute: 0)).hasTime,
        isTrue,
      );
      expect(_makeAnnouncement().hasTime, isFalse);
    });

    test('isStale after 4 hours when unverified', () {
      final stale = _makeAnnouncement(
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        verificationState: 'unverified',
      );
      expect(stale.isStale, isTrue);
    });

    test('not stale if verified', () {
      final notStale = _makeAnnouncement(
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        verificationState: 'verified',
      );
      expect(notStale.isStale, isFalse);
    });

    test('not stale if recent', () {
      final recent = _makeAnnouncement(
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        verificationState: 'unverified',
      );
      expect(recent.isStale, isFalse);
    });
  });

  group('googleCalendarUrl', () {
    test('contains title and course code', () {
      final ann = _makeAnnouncement(description: 'Quiz on Chapter 5');
      final url = ann.googleCalendarUrl;

      expect(url, contains('calendar.google.com'));
      expect(url, contains(Uri.encodeComponent('Test Announcement')));
      expect(url, contains(Uri.encodeComponent('CS F111')));
    });

    test('includes section info when section-specific', () {
      final ann = _makeAnnouncement(sectionId: 'L1');
      final url = ann.googleCalendarUrl;

      expect(url, contains(Uri.encodeComponent('Test Announcement (L1)')));
    });

    test('uses date range for all-day events', () {
      final ann = _makeAnnouncement(
        eventDate: DateTime(2026, 3, 15),
      );
      final url = ann.googleCalendarUrl;

      expect(url, contains('20260315/20260316'));
    });

    test('uses datetime range for timed events', () {
      final ann = _makeAnnouncement(
        eventDate: DateTime(2026, 3, 15),
        startTime: const TimeOfDay(hour: 9, minute: 30),
        endTime: const TimeOfDay(hour: 10, minute: 30),
      );
      final url = ann.googleCalendarUrl;

      expect(url, contains('20260315T093000/20260315T103000'));
    });

    test('defaults to 1 hour duration when no end time', () {
      final ann = _makeAnnouncement(
        eventDate: DateTime(2026, 3, 15),
        startTime: const TimeOfDay(hour: 14, minute: 0),
      );
      final url = ann.googleCalendarUrl;

      expect(url, contains('20260315T140000/20260315T150000'));
    });
  });

  group('defaults', () {
    test('default confidence is fairly_sure', () {
      final ann = _makeAnnouncement();
      expect(ann.confidence, 'fairly_sure');
    });

    test('default disputeState is undisputed', () {
      final ann = _makeAnnouncement();
      expect(ann.disputeState, 'undisputed');
    });

    test('default verificationState is unverified', () {
      final ann = _makeAnnouncement();
      expect(ann.verificationState, 'unverified');
    });

    test('default vote counts are 0', () {
      final ann = _makeAnnouncement();
      expect(ann.upvotes, 0);
      expect(ann.downvotes, 0);
      expect(ann.confirmWeight, 0);
      expect(ann.denyWeight, 0);
    });
  });
}
