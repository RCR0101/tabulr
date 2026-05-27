import '../utils/datetime_utils.dart';

class Announcement {
  final String topWidget;
  final DateTime lastUpdated;

  const Announcement({
    required this.topWidget,
    required this.lastUpdated,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      topWidget: json['topWidget'] ?? '',
      lastUpdated: parseDateTime(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'topWidget': topWidget,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}
