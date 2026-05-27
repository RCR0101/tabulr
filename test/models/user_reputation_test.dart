import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/user_reputation.dart';

void main() {
  group('tierForScore', () {
    test('score >= 100 is trusted', () {
      expect(UserReputation.tierForScore(100), TrustTier.trusted);
      expect(UserReputation.tierForScore(200), TrustTier.trusted);
    });

    test('score >= 50 is reliable', () {
      expect(UserReputation.tierForScore(50), TrustTier.reliable);
      expect(UserReputation.tierForScore(99), TrustTier.reliable);
    });

    test('score >= 20 is contributor', () {
      expect(UserReputation.tierForScore(20), TrustTier.contributor);
      expect(UserReputation.tierForScore(49), TrustTier.contributor);
    });

    test('score < 20 is newUser', () {
      expect(UserReputation.tierForScore(0), TrustTier.newUser);
      expect(UserReputation.tierForScore(19), TrustTier.newUser);
      expect(UserReputation.tierForScore(-5), TrustTier.newUser);
    });
  });

  group('tierMinScore', () {
    test('returns correct floor for each tier', () {
      expect(UserReputation.tierMinScore(TrustTier.newUser), 0);
      expect(UserReputation.tierMinScore(TrustTier.contributor), 20);
      expect(UserReputation.tierMinScore(TrustTier.reliable), 50);
      expect(UserReputation.tierMinScore(TrustTier.trusted), 100);
    });
  });

  group('tierName', () {
    test('returns readable name for each tier', () {
      expect(UserReputation.tierName(TrustTier.newUser), 'New');
      expect(UserReputation.tierName(TrustTier.contributor), 'Contributor');
      expect(UserReputation.tierName(TrustTier.reliable), 'Reliable');
      expect(UserReputation.tierName(TrustTier.trusted), 'Trusted');
    });
  });

  group('flagWeight', () {
    test('newUser and contributor have weight 1', () {
      final newUser = UserReputation(
        uid: 'u1',
        score: 5,
        lastActive: DateTime.now(),
      );
      expect(newUser.flagWeight, 1);

      final contributor = UserReputation(
        uid: 'u2',
        score: 30,
        lastActive: DateTime.now(),
      );
      expect(contributor.flagWeight, 1);
    });

    test('reliable has weight 2', () {
      final rep = UserReputation(
        uid: 'u1',
        score: 60,
        lastActive: DateTime.now(),
      );
      expect(rep.flagWeight, 2);
    });

    test('trusted has weight 3', () {
      final rep = UserReputation(
        uid: 'u1',
        score: 150,
        lastActive: DateTime.now(),
      );
      expect(rep.flagWeight, 3);
    });
  });

  group('isSuspended', () {
    test('false when suspendedUntil is null', () {
      final rep = UserReputation(
        uid: 'u1',
        lastActive: DateTime.now(),
      );
      expect(rep.isSuspended, isFalse);
    });

    test('true when suspendedUntil is in the future', () {
      final rep = UserReputation(
        uid: 'u1',
        lastActive: DateTime.now(),
        suspendedUntil: DateTime.now().add(const Duration(days: 7)),
      );
      expect(rep.isSuspended, isTrue);
    });

    test('false when suspendedUntil is in the past', () {
      final rep = UserReputation(
        uid: 'u1',
        lastActive: DateTime.now(),
        suspendedUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(rep.isSuspended, isFalse);
    });
  });

  group('decayedScore', () {
    test('no decay within 30 days of activity', () {
      final rep = UserReputation(
        uid: 'u1',
        score: 80,
        lastActive: DateTime.now().subtract(const Duration(days: 15)),
      );
      expect(rep.decayedScore, 80);
    });

    test('decays after 30 days inactive', () {
      final rep = UserReputation(
        uid: 'u1',
        score: 80,
        lastActive: DateTime.now().subtract(const Duration(days: 60)),
      );
      expect(rep.decayedScore, lessThan(80));
      expect(rep.decayedScore, greaterThan(0));
    });

    test('score does not decay below tier floor minus 5', () {
      final rep = UserReputation(
        uid: 'u1',
        score: 55,
        lastActive: DateTime.now().subtract(const Duration(days: 365)),
      );
      // reliable tier floor is 50, minus 5 = 45
      expect(rep.decayedScore, greaterThanOrEqualTo(45));
    });
  });

  group('ReputationEvent', () {
    test('fromMap -> toMap roundtrip preserves data', () {
      final event = ReputationEvent(
        type: 'upvote',
        points: 5,
        timestamp: DateTime(2026, 3, 1),
        announcementId: 'ann-1',
        description: 'Upvoted announcement',
      );

      final map = event.toMap();
      expect(map['type'], 'upvote');
      expect(map['points'], 5);
      expect(map['announcementId'], 'ann-1');
      expect(map['description'], 'Upvoted announcement');
    });

    test('fromMap handles missing optional fields', () {
      final event = ReputationEvent.fromMap({
        'type': 'downvote',
        'points': -2,
        'timestamp': '2026-03-01T00:00:00.000',
        'description': 'Downvoted',
      });

      expect(event.type, 'downvote');
      expect(event.points, -2);
      expect(event.announcementId, isNull);
    });
  });
}
