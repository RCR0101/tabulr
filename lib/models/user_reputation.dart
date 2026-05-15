import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color, Colors;

enum TrustTier { newUser, contributor, reliable, trusted }

class ReputationEvent {
  final String type;
  final int points;
  final DateTime timestamp;
  final String? announcementId;
  final String description;

  const ReputationEvent({
    required this.type,
    required this.points,
    required this.timestamp,
    this.announcementId,
    required this.description,
  });

  factory ReputationEvent.fromMap(Map<String, dynamic> map) {
    return ReputationEvent(
      type: map['type'] ?? '',
      points: map['points'] ?? 0,
      timestamp: _parseTimestamp(map['timestamp']),
      announcementId: map['announcementId'],
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'points': points,
        'timestamp': Timestamp.fromDate(timestamp),
        'announcementId': announcementId,
        'description': description,
      };

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}

class UserReputation {
  final String uid;
  final int score;
  final DateTime lastActive;
  final DateTime? suspendedUntil;
  final List<ReputationEvent> events;

  const UserReputation({
    required this.uid,
    this.score = 0,
    required this.lastActive,
    this.suspendedUntil,
    this.events = const [],
  });

  factory UserReputation.empty(String uid) => UserReputation(
        uid: uid,
        lastActive: DateTime.now(),
      );

  factory UserReputation.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final eventsList = (data['events'] as List<dynamic>?)
            ?.map((e) => ReputationEvent.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];
    return UserReputation(
      uid: doc.id,
      score: data['score'] ?? 0,
      lastActive: _parseTs(data['lastActive']),
      suspendedUntil: data['suspendedUntil'] != null
          ? _parseTs(data['suspendedUntil'])
          : null,
      events: eventsList,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'score': score,
        'lastActive': Timestamp.fromDate(lastActive),
        'suspendedUntil': suspendedUntil != null
            ? Timestamp.fromDate(suspendedUntil!)
            : null,
        'events': events.map((e) => e.toMap()).toList(),
      };

  bool get isSuspended =>
      suspendedUntil != null && DateTime.now().isBefore(suspendedUntil!);

  int get decayedScore {
    final inactiveDays = DateTime.now().difference(lastActive).inDays;
    if (inactiveDays < 30) return score;
    final weeksInactive = (inactiveDays - 30) ~/ 7 + 1;
    final tierFloor = tierMinScore(tier) - 5;
    var s = score;
    for (var i = 0; i < weeksInactive; i++) {
      s = (s * 0.95).round();
      if (s <= tierFloor) return tierFloor < 0 ? tierFloor : tierFloor;
    }
    return s;
  }

  TrustTier get tier => tierForScore(decayedScore);

  int get flagWeight {
    switch (tier) {
      case TrustTier.newUser:
      case TrustTier.contributor:
        return 1;
      case TrustTier.reliable:
        return 2;
      case TrustTier.trusted:
        return 3;
    }
  }

  static TrustTier tierForScore(int score) {
    if (score >= 100) return TrustTier.trusted;
    if (score >= 50) return TrustTier.reliable;
    if (score >= 20) return TrustTier.contributor;
    return TrustTier.newUser;
  }

  static String tierName(TrustTier tier) {
    switch (tier) {
      case TrustTier.newUser:
        return 'New';
      case TrustTier.contributor:
        return 'Contributor';
      case TrustTier.reliable:
        return 'Reliable';
      case TrustTier.trusted:
        return 'Trusted';
    }
  }

  static Color tierColor(TrustTier tier) {
    switch (tier) {
      case TrustTier.newUser:
        return Colors.grey;
      case TrustTier.contributor:
        return Colors.blue;
      case TrustTier.reliable:
        return Colors.green;
      case TrustTier.trusted:
        return const Color(0xFFD4AF37);
    }
  }

  static int tierMinScore(TrustTier tier) {
    switch (tier) {
      case TrustTier.newUser:
        return 0;
      case TrustTier.contributor:
        return 20;
      case TrustTier.reliable:
        return 50;
      case TrustTier.trusted:
        return 100;
    }
  }

  static DateTime _parseTs(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}
