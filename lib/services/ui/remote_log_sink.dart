import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../constants/app_constants.dart';

/// Signature for the network call that ships a batch of log entries. Injectable
/// so tests can capture payloads without hitting the network.
typedef LogPoster = Future<void> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

/// Buffers structured log records and flushes them to the Cloudflare logger
/// worker, which persists each batch as a JSON object in the R2 logs bucket
/// (`/log` endpoint -> `logs/<date>/log-*.json`).
///
/// This is the single remote transport for both [SecureLogger] (every app log
/// at or above [minLevel]) and the admin audit trail. It must never call back
/// into SecureLogger on failure — doing so would recurse into this sink — so
/// errors fall back to [debugPrint].
class RemoteLogSink {
  static final RemoteLogSink _instance = RemoteLogSink._();
  factory RemoteLogSink() => _instance;
  RemoteLogSink._();

  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  bool _initialized = false;
  bool _enabled = false;
  String _workerUrl = AppUrls.perfLoggerWorker;
  String? _apiKey;

  /// App-specific user id (e.g. "f20220123H" — see
  /// AuthService.deriveUserDocId), stamped onto every buffered record so log
  /// entries in R2 are attributable to a session. This is the *app* id, never
  /// the Firebase UID. Null for guests / signed-out users. Set by AuthService
  /// on auth-state changes; a plain setter keeps this sink free of any Firebase
  /// dependency.
  String? _userId;
  void setUserId(String? userId) => _userId = userId;

  /// Records below this level are dropped before buffering. Defaults to info so
  /// debug spam never reaches R2.
  int minLevelIndex = 1; // LogLevel.info

  /// Overridable network sender. Defaults to a real HTTP POST.
  @visibleForTesting
  LogPoster poster = _defaultPoster;

  static Future<void> _defaultPoster(
      Uri url, Map<String, String> headers, String body) async {
    await http.post(url, headers: headers, body: body);
  }

  /// Configure and start the periodic flush. Idempotent.
  void initialize({
    String? workerUrl,
    String? apiKey,
    bool enabled = true,
    int? minLevelIndex,
  }) {
    if (_initialized) return;
    _initialized = true;
    _enabled = enabled;
    if (workerUrl != null) _workerUrl = workerUrl;
    _apiKey = apiKey;
    if (minLevelIndex != null) this.minLevelIndex = minLevelIndex;
    if (!_enabled) return;
    _flushTimer = Timer.periodic(AppDurations.logFlushInterval, (_) => flush());
  }

  bool get isEnabled => _enabled;

  @visibleForTesting
  int get bufferLength => _buffer.length;

  /// Queue a single structured record. [levelIndex] mirrors `LogLevel.index`
  /// (debug=0, info=1, warning=2, error=3, critical=4).
  void enqueue(Map<String, dynamic> record, {int levelIndex = 1}) {
    if (!_enabled) return;
    if (levelIndex < minLevelIndex) return;

    // Stamp the current app-user id so every entry is attributable, whichever
    // source enqueued it (SecureLogger, admin audit, perf). Absent for guests.
    if (_userId != null) record['userId'] = _userId;

    _buffer.add(record);

    if (_buffer.length >= AppLimits.logFlushThreshold) {
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

      await poster(
        Uri.parse('$_workerUrl/log'),
        headers,
        jsonEncode({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'entries': batch,
          'metadata': {
            'platform': defaultTargetPlatform.name,
            'isWeb': kIsWeb,
            'debugMode': kDebugMode,
          },
        }),
      );
    } catch (e) {
      // Never route through SecureLogger here — it would recurse into enqueue().
      // Console output only in local dev (no device/web release noise).
      if (kDebugMode) {
        debugPrint('[RemoteLogSink] flush failed: $e');
      }
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_enabled) flush();
  }

  @visibleForTesting
  void resetForTest() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _buffer.clear();
    _initialized = false;
    _enabled = false;
    _apiKey = null;
    _userId = null;
    minLevelIndex = 1;
    poster = _defaultPoster;
  }
}
