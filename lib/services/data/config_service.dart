import '../ui/secure_logger.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  String get googleWebClientId => '497813124701-d5v3q5knljt4svch4l0b5q0cgv71o22l.apps.googleusercontent.com';

  // App Configuration
  String get appName => 'Tabulr';
  // Keep in sync with pubspec.yaml `version:` field.
  String get appVersion => '2.0.2';

  // Debug Settings
  bool get debugMode => false;
  bool get enableAnalytics => true;

  // Semester dates
  DateTime get semesterStart => DateTime(2026, 1, 5);
  DateTime get semesterEnd => DateTime(2026, 5, 16);
  DateTime get midsemStart => DateTime(2026, 3, 9);
  DateTime get midsemEnd => DateTime(2026, 3, 14);
  DateTime get endsemStart => DateTime(2026, 5, 2);
  DateTime get endsemEnd => DateTime(2026, 5, 16);

  List<Map<String, DateTime>> get breakPeriods => [
        {'start': midsemStart, 'end': midsemEnd},
        {'start': endsemStart, 'end': endsemEnd},
      ];

  bool get isValidConfiguration => googleWebClientId.isNotEmpty;

  void printConfiguration() {
    if (debugMode) {
      SecureLogger.debug('CONFIG', 'App: $appName v$appVersion, debug=$debugMode, analytics=$enableAnalytics');
    }
  }
}