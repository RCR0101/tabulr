import 'package:flutter/foundation.dart';
import '../services/firestore_service.dart';
import '../services/secure_logger.dart';
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


class AnnouncementService extends ChangeNotifier {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  final FirestoreService _firestoreService = FirestoreService();
  
  Announcement? _currentAnnouncement;
  bool _isLoading = false;
  String? _error;

  Announcement? get currentAnnouncement => _currentAnnouncement;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch the latest announcement from Firebase
  Future<void> fetchAnnouncement() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final doc = await _firestoreService.getDocument('metadata', 'announcement');
      
      if (doc != null && doc.exists && doc.data() != null) {
        _currentAnnouncement = Announcement.fromJson(doc.data()!);
        SecureLogger.info('ANNOUNCEMENT', 'Fetched announcement successfully');
      } else {
        _currentAnnouncement = null;
        SecureLogger.info('ANNOUNCEMENT', 'No announcement document found');
      }
    } catch (e) {
      _error = 'Failed to fetch announcement: $e';
      SecureLogger.error('ANNOUNCEMENT', 'Failed to fetch announcement', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if announcement should be shown to the user
  /// Returns true if:
  /// 1. There is an announcement with non-empty topWidget text
  /// 2. User hasn't dismissed it after the announcement's lastUpdated time
  bool shouldShowAnnouncement(DateTime? userDismissedAt) {
    if (_currentAnnouncement == null || _currentAnnouncement!.topWidget.trim().isEmpty) {
      return false;
    }

    if (userDismissedAt == null) {
      return true; // User never dismissed any announcement
    }

    // Show if announcement was updated after user dismissed
    return _currentAnnouncement!.lastUpdated.isAfter(userDismissedAt);
  }

  /// Get the announcement text, or null if no announcement should be shown
  String? getAnnouncementText(DateTime? userDismissedAt) {
    if (!shouldShowAnnouncement(userDismissedAt)) {
      return null;
    }
    
    return _currentAnnouncement!.topWidget;
  }

  /// Watch for real-time announcement updates
  Stream<Announcement?> watchAnnouncement() {
    return _firestoreService.watchDocument('metadata', 'announcement').map((doc) {
      if (doc.exists && doc.data() != null) {
        final announcement = Announcement.fromJson(doc.data()!);
        _currentAnnouncement = announcement;
        return announcement;
      } else {
        _currentAnnouncement = null;
        return null;
      }
    });
  }

  /// Clear any cached data
  void clearCache() {
    _currentAnnouncement = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}