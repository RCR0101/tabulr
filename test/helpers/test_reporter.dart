import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TestReporter {
  static final String _workerUrl = Platform.environment['TEST_LOGGER_URL'] ??
      'https://test-logger.tabulr.workers.dev';
  static final String _apiKey =
      Platform.environment['TEST_LOGGER_API_KEY'] ?? '';

  static Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    if (_apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $_apiKey';
    return headers;
  }

  static Future<void> reportTestResults(
    String suite,
    List<Map<String, dynamic>> results,
  ) async {
    try {
      await http.post(
        Uri.parse('$_workerUrl/test'),
        headers: _headers(),
        body: jsonEncode({
          'suite': suite,
          'results': results,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'metadata': {
            'ci': Platform.environment.containsKey('CI'),
            'commit': Platform.environment['GITHUB_SHA'] ?? 'local',
            'runner': 'flutter_test',
          },
        }),
      );
    } catch (_) {}
  }

  static Future<void> reportPerfMetrics(
    List<Map<String, dynamic>> metrics,
  ) async {
    try {
      await http.post(
        Uri.parse('$_workerUrl/perf'),
        headers: _headers(),
        body: jsonEncode({
          'metrics': metrics,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'metadata': {
            'ci': Platform.environment.containsKey('CI'),
            'commit': Platform.environment['GITHUB_SHA'] ?? 'local',
            'runner': 'flutter_test',
          },
        }),
      );
    } catch (_) {}
  }

  static String classify(int ms) =>
      ms > 5000 ? 'slow' : ms > 1000 ? 'medium' : 'fast';
}
