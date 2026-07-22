import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/bug_report.dart';

void main() {
  BugReport report({DateTime? adminAt, DateTime? userAt}) => BugReport(
        id: 'r1',
        authorUid: 'f20242005H',
        authorEmail: 'f20242005@hyderabad.bits-pilani.ac.in',
        category: 'CGPA Calculator',
        subCategory: 'Wrong calculation',
        description: 'CG differs from ERP',
        status: BugStatus.pending,
        createdAt: DateTime(2026, 7, 21, 14, 31),
        lastAdminReplyAt: adminAt,
        lastUserReplyAt: userAt,
      );

  group('BugStatus', () {
    test('fromId round-trips every status', () {
      for (final s in BugStatus.values) {
        expect(BugStatus.fromId(s.id), s);
      }
    });

    test('fromId falls back to pending for unknown or null ids', () {
      expect(BugStatus.fromId('not_a_status'), BugStatus.pending);
      expect(BugStatus.fromId(null), BugStatus.pending);
    });
  });

  group('unread flags', () {
    test('a fresh report with no replies is unread for nobody', () {
      final r = report();
      expect(r.hasUnreadForUser, isFalse);
      expect(r.hasUnreadForAdmin, isFalse);
    });

    test('an admin reply is unread for the user only', () {
      final r = report(adminAt: DateTime(2026, 7, 22, 9));
      expect(r.hasUnreadForUser, isTrue);
      expect(r.hasUnreadForAdmin, isFalse);
    });

    test('the user replying back clears theirs and flags the admin', () {
      final r = report(
        adminAt: DateTime(2026, 7, 22, 9),
        userAt: DateTime(2026, 7, 22, 10),
      );
      expect(r.hasUnreadForUser, isFalse);
      expect(r.hasUnreadForAdmin, isTrue);
    });

    test('the admin answering again flips it back', () {
      final r = report(
        adminAt: DateTime(2026, 7, 22, 11),
        userAt: DateTime(2026, 7, 22, 10),
      );
      expect(r.hasUnreadForUser, isTrue);
      expect(r.hasUnreadForAdmin, isFalse);
    });

    test('a user reply with no admin reply yet flags the admin', () {
      final r = report(userAt: DateTime(2026, 7, 22, 10));
      expect(r.hasUnreadForAdmin, isTrue);
      expect(r.hasUnreadForUser, isFalse);
    });
  });

  group('BugReport.toCreateMap', () {
    test('always files as pending regardless of the in-memory status', () {
      final map = BugReport(
        id: '',
        authorUid: 'u1',
        authorEmail: 'a@hyderabad.bits-pilani.ac.in',
        category: 'Other',
        subCategory: 'General feedback',
        description: 'hi',
        // Even if a caller passes something else, the wire payload must be
        // pending — firestore.rules rejects a create with any other status.
        status: BugStatus.fixed,
        createdAt: DateTime(2026, 7, 21),
      ).toCreateMap();

      expect(map['status'], BugStatus.pending.id);
      expect(map['authorUid'], 'u1');
      expect(map['description'], 'hi');
    });
  });

  group('taxonomy', () {
    test('every category has at least one sub-category', () {
      expect(bugReportTaxonomy, isNotEmpty);
      for (final entry in bugReportTaxonomy.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} has no options');
      }
    });

    test('labels stay within the length firestore.rules allows', () {
      for (final entry in bugReportTaxonomy.entries) {
        expect(entry.key.length, lessThan(100));
        for (final sub in entry.value) {
          expect(sub.length, lessThan(100));
        }
      }
    });
  });
}
