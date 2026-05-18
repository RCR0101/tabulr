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

  bool get isValidConfiguration => googleWebClientId.isNotEmpty;

  void printConfiguration() {
    if (debugMode) {
      SecureLogger.debug('CONFIG', 'App: $appName v$appVersion, debug=$debugMode, analytics=$enableAnalytics');
    }
  }
}