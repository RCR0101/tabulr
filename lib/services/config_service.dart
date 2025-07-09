import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  // Only handle Google Web Client ID here
  // Firebase configuration is handled in firebase_options.dart
  String get googleWebClientId => '497813124701-d5v3q5knljt4svch4l0b5q0cgv71o22l.apps.googleusercontent.com';

  // Firestore Configuration
  String get firestoreTimetablesCollection => dotenv.env['FIRESTORE_TIMETABLES_COLLECTION'] ?? 'user_timetables';
  String get coursesCollection => dotenv.env['COURSES_COLLECTION'] ?? 'courses';
  String get timetableMetadataCollection => dotenv.env['TIMETABLE_METADATA_COLLECTION'] ?? 'timetable_metadata';

  // App Configuration
  String get appName => dotenv.env['APP_NAME'] ?? 'Tabulr';
  String get appVersion => dotenv.env['APP_VERSION'] ?? '1.0.0';

  // Debug Settings
  bool get debugMode => dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
  bool get enableAnalytics => dotenv.env['ENABLE_ANALYTICS']?.toLowerCase() != 'false';

  // Simple validation for Google Web Client ID only
  bool get isValidConfiguration => googleWebClientId.isNotEmpty;

  void printConfiguration() {
    if (debugMode) {
      print('=== Configuration ===');
      print('App Name: $appName');
      print('App Version: $appVersion');
      print('Debug Mode: $debugMode');
      print('Enable Analytics: $enableAnalytics');
      print('Firestore Collection: $firestoreTimetablesCollection');
      print('Google Web Client ID: ${googleWebClientId.isNotEmpty ? "Set" : "Missing"}');
      print('=====================');
    }
  }
}