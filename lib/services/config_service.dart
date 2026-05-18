import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'secure_logger.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  String get googleWebClientId => '497813124701-d5v3q5knljt4svch4l0b5q0cgv71o22l.apps.googleusercontent.com';

  // App Configuration
  String get appName => dotenv.env['APP_NAME'] ?? 'Tabulr';
  String get appVersion => dotenv.env['APP_VERSION'] ?? '1.0.0';

  // Debug Settings
  bool get debugMode => dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
  bool get enableAnalytics => dotenv.env['ENABLE_ANALYTICS']?.toLowerCase() != 'false';

  // Semester dates
  DateTime get semesterStart =>
      DateTime.tryParse(dotenv.env['SEMESTER_START'] ?? '') ??
      DateTime(2026, 1, 5);

  DateTime get semesterEnd =>
      DateTime.tryParse(dotenv.env['SEMESTER_END'] ?? '') ??
      DateTime(2026, 5, 16);

  DateTime get midsemStart =>
      DateTime.tryParse(dotenv.env['MIDSEM_START'] ?? '') ??
      DateTime(2026, 3, 9);

  DateTime get midsemEnd =>
      DateTime.tryParse(dotenv.env['MIDSEM_END'] ?? '') ??
      DateTime(2026, 3, 14);

  DateTime get endsemStart =>
      DateTime.tryParse(dotenv.env['ENDSEM_START'] ?? '') ??
      DateTime(2026, 5, 2);

  DateTime get endsemEnd =>
      DateTime.tryParse(dotenv.env['ENDSEM_END'] ?? '') ??
      DateTime(2026, 5, 16);

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