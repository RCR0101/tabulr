import 'package:cloud_firestore/cloud_firestore.dart';

class AnnouncementFlag {
  final String uid;
  final String reason;
  final String? counterSourceUrl;
  final String confidence;
  final int weight;
  final DateTime timestamp;

  const AnnouncementFlag({
    required this.uid,
    required this.reason,
    this.counterSourceUrl,
    required this.confidence,
    required this.weight,
    required this.timestamp,
  });

  factory AnnouncementFlag.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AnnouncementFlag(
      uid: doc.id,
      reason: data['reason'] ?? '',
      counterSourceUrl: data['counterSourceUrl'],
      confidence: data['confidence'] ?? 'fairly_sure',
      weight: data['weight'] ?? 1,
      timestamp: _parseTs(data['timestamp']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'reason': reason,
        'counterSourceUrl': counterSourceUrl,
        'confidence': confidence,
        'weight': weight,
        'timestamp': FieldValue.serverTimestamp(),
      };

  bool get isCertain => confidence == 'certain';

  static DateTime _parseTs(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}
