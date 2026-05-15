import 'package:cloud_firestore/cloud_firestore.dart';

enum VerificationType { confirm, deny }

class AnnouncementVerification {
  final String uid;
  final VerificationType type;
  final String? note;
  final int weight;
  final DateTime timestamp;

  const AnnouncementVerification({
    required this.uid,
    required this.type,
    this.note,
    required this.weight,
    required this.timestamp,
  });

  factory AnnouncementVerification.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AnnouncementVerification(
      uid: doc.id,
      type: data['type'] == 'deny' ? VerificationType.deny : VerificationType.confirm,
      note: data['note'],
      weight: data['weight'] ?? 1,
      timestamp: _parseTs(data['timestamp']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type == VerificationType.confirm ? 'confirm' : 'deny',
        'note': note,
        'weight': weight,
        'timestamp': FieldValue.serverTimestamp(),
      };

  static DateTime _parseTs(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}
