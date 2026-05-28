import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'secure_logger.dart';

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._();

  static const String _defaultWorkerUrl = 'https://test-logger.dalmia-aryan.workers.dev';
  static const int _flushThreshold = 50;
  static const Duration _flushInterval = Duration(seconds: 30);

  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  bool _initialized = false;
  bool _enabled = false;
  String _workerUrl = _defaultWorkerUrl;
  String? _apiKey;

  void initialize({String? workerUrl, String? apiKey, bool? enabled}) {
    if (_initialized) return;
    _initialized = true;

    // Disabled in release mode unless explicitly enabled
    _enabled = enabled ?? kDebugMode;
    if (!_enabled) return;

    if (workerUrl != null) _workerUrl = workerUrl;
    _apiKey = apiKey;
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  bool get isEnabled => _enabled;

  void record(String operation, int durationMs, String classification, [Map<String, dynamic>? metadata]) {
    if (!_enabled) return;

    _buffer.add({
      'operation': operation,
      'duration_ms': durationMs,
      'classification': classification,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (metadata != null) ...metadata,
    });

    if (_buffer.length >= _flushThreshold) {
      flush();
    }
  }

  Future<void> flush() async {
    if (!_enabled || _buffer.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
      };

      await http.post(
        Uri.parse('$_workerUrl/perf'),
        headers: headers,
        body: jsonEncode({
          'type': 'performance',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'metrics': batch,
          'metadata': {
            'platform': defaultTargetPlatform.name,
            'isWeb': kIsWeb,
            'debugMode': kDebugMode,
          },
        }),
      );
    } catch (e) {
      SecureLogger.error('PerformanceMonitor', 'Flush failed', e);
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    if (_enabled) flush();
  }
}
