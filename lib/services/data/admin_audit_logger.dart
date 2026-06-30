import 'package:flutter/foundation.dart';
import '../ui/secure_logger.dart';
import '../ui/remote_log_sink.dart';
import 'auth_service.dart';

/// Outcome classification for an admin action.
enum AuditOutcome { success, warning, error }

extension AuditOutcomeLabel on AuditOutcome {
  String get label {
    switch (this) {
      case AuditOutcome.success:
        return 'SUCCESS';
      case AuditOutcome.warning:
        return 'WARNING';
      case AuditOutcome.error:
        return 'ERROR';
    }
  }
}

/// A single audit record: what action was taken, what it resulted in,
/// the outcome severity, and who was responsible.
@immutable
class AuditEntry {
  /// When the action completed (UTC).
  final DateTime timestamp;

  /// Identity of the admin responsible (email, falling back to uid, else
  /// 'unknown'). Never empty.
  final String actor;

  /// Machine-friendly action name, e.g. 'upload_timetable'.
  final String action;

  /// Human-readable description of what the action resulted in.
  final String result;

  /// Severity of the outcome.
  final AuditOutcome outcome;

  /// Optional structured context (non-sensitive).
  final Map<String, dynamic>? details;

  const AuditEntry({
    required this.timestamp,
    required this.actor,
    required this.action,
    required this.result,
    required this.outcome,
    this.details,
  });

  /// Single-line, log-friendly representation.
  String format() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('[${outcome.label}] ')
      ..write('[$actor] ')
      ..write('$action — $result');
    if (details != null && details!.isNotEmpty) {
      buffer.write(' | $details');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'actor': actor,
        'action': action,
        'result': result,
        'outcome': outcome.label,
        if (details != null) 'details': details,
      };
}

/// Records admin-dashboard actions to an in-memory audit trail (newest first)
/// and forwards them to [SecureLogger]. Each entry captures the action, its
/// result, an outcome level (SUCCESS / WARNING / ERROR), and the responsible
/// admin.
///
/// The actor is resolved lazily via [actorResolver]; the default reads the
/// signed-in user from [AuthService]. Tests can override it to avoid touching
/// Firebase.
class AdminAuditLogger extends ChangeNotifier {
  static final AdminAuditLogger _instance = AdminAuditLogger._internal();
  factory AdminAuditLogger() => _instance;
  AdminAuditLogger._internal();

  static const String _category = 'ADMIN_AUDIT';

  /// Maximum number of entries retained in memory.
  static const int maxEntries = 200;

  /// Resolves the current admin's identity. Overridable for testing.
  String Function() actorResolver = _defaultActorResolver;

  final List<AuditEntry> _entries = [];

  /// Audit trail, newest first.
  List<AuditEntry> get entries => List.unmodifiable(_entries);

  static String _defaultActorResolver() {
    try {
      final user = AuthService().currentUser;
      return user?.email ?? user?.uid ?? 'unknown';
    } catch (_) {
      // AuthService/Firebase unavailable (e.g. during tests or early startup).
      return 'unknown';
    }
  }

  /// Log a successful admin action.
  void success(String action, String result, [Map<String, dynamic>? details]) =>
      _record(AuditOutcome.success, action, result, details);

  /// Log an admin action that completed with a caveat worth noting.
  void warning(String action, String result, [Map<String, dynamic>? details]) =>
      _record(AuditOutcome.warning, action, result, details);

  /// Log a failed admin action. [error] is appended to the details.
  void error(String action, String result,
      [Object? error, Map<String, dynamic>? details]) {
    final merged = <String, dynamic>{...?details};
    if (error != null) merged['error'] = error.toString();
    _record(AuditOutcome.error, action, result, merged.isEmpty ? null : merged);
  }

  void _record(AuditOutcome outcome, String action, String result,
      Map<String, dynamic>? details) {
    String actor;
    try {
      actor = actorResolver();
    } catch (_) {
      actor = 'unknown';
    }
    if (actor.isEmpty) actor = 'unknown';

    final entry = AuditEntry(
      timestamp: DateTime.now().toUtc(),
      actor: actor,
      action: action,
      result: result,
      outcome: outcome,
      details: details,
    );

    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }

    _forwardToSecureLogger(entry);
    _forwardToRemoteSink(entry);
    notifyListeners();
  }

  /// Sends the full, *unmasked* audit record to the remote logger worker so the
  /// R2 trail preserves the responsible admin's identity. (The SecureLogger
  /// path also reaches R2, but masks the actor's email.)
  void _forwardToRemoteSink(AuditEntry entry) {
    try {
      final levelIndex = entry.outcome == AuditOutcome.error
          ? 3 // error
          : entry.outcome == AuditOutcome.warning
              ? 2 // warning
              : 1; // info
      RemoteLogSink().enqueue({
        'source': 'admin_audit',
        ...entry.toJson(),
      }, levelIndex: levelIndex);
    } catch (_) {
      // Sink unavailable; the in-memory trail and SecureLogger copy still exist.
    }
  }

  void _forwardToSecureLogger(AuditEntry entry) {
    final context = <String, dynamic>{
      'actor': entry.actor,
      'action': entry.action,
      'result': entry.result,
      if (entry.details != null) ...entry.details!,
    };
    switch (entry.outcome) {
      case AuditOutcome.success:
        SecureLogger.info(_category, '${entry.action}: ${entry.result}', context);
        break;
      case AuditOutcome.warning:
        SecureLogger.warning(_category, '${entry.action}: ${entry.result}', context);
        break;
      case AuditOutcome.error:
        SecureLogger.error(_category, '${entry.action}: ${entry.result}', null, null, context);
        break;
    }
  }

  /// Clears the in-memory trail. Does not affect already-emitted logs.
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
