import 'package:flutter/foundation.dart';
import 'dart:convert';

/// Log levels with priority ordering
enum LogLevel { debug, info, warning, error, critical }

/// Logging configuration
class LogConfig {
  static LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  static bool enableStackTraces = kDebugMode;
  static bool enablePerformanceLogging = true;
  static int maxMessageLength = 1000;
  static int maxContextLength = 500;
}

/// Secure logging service that prevents PII exposure and provides structured logging
class SecureLogger {
  static const String _tag = 'TimetableMaker';
  
  // Compiled regex patterns for performance
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
    caseSensitive: false
  );
  static final RegExp _uidPattern = RegExp(r'\b[A-Za-z0-9_-]{20,}\b');
  static final RegExp _phonePattern = RegExp(r'\b\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b');
  static final RegExp _displayNamePattern = RegExp(r'displayName[:\s]*["\047](.*?)["\047]', caseSensitive: false);
  static final RegExp _userIdPattern = RegExp(r'user(?:Id)?[:\s]+([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,})', caseSensitive: false);
  static final RegExp _sensitiveKeyPattern = RegExp(r'\b(?:password|token|secret|key|credential|auth|bearer)\b', caseSensitive: false);
  
  // Sensitive field names to exclude from context
  static final Set<String> _sensitiveFields = {
    'password', 'token', 'secret', 'key', 'credential', 'auth', 'bearer',
    'authorization', 'apikey', 'api_key', 'accesstoken', 'access_token',
    'refreshtoken', 'refresh_token', 'sessionid', 'session_id'
  };
  
  /// Check if running in debug mode
  static bool get _isDebugMode => kDebugMode;
  
  /// Check if running in production
  static bool get _isProduction => kReleaseMode;
  
  /// Check if a log level should be processed
  static bool _shouldLog(LogLevel level) {
    return level.index >= LogConfig.minLevel.index;
  }
  
  /// Safely convert any object to string with length limit
  static String _safeToString(dynamic obj, {int? maxLength}) {
    if (obj == null) return 'null';
    
    try {
      String result;
      if (obj is String) {
        result = obj;
      } else if (obj is Map || obj is List) {
        result = jsonEncode(obj);
      } else {
        result = obj.toString();
      }
      
      final limit = maxLength ?? LogConfig.maxMessageLength;
      if (result.length > limit) {
        return '${result.substring(0, limit)}...';
      }
      return result;
    } catch (e) {
      return '[Object: ${obj.runtimeType}]';
    }
  }
  
  /// Comprehensive PII sanitization
  static String _sanitizePII(String message) {
    if (message.isEmpty) return message;
    
    try {
      return message
          // Replace email addresses with masked version
          .replaceAllMapped(_emailPattern, (match) {
            final email = match.group(0) ?? '';
            final parts = email.split('@');
            if (parts.length == 2) {
              final local = parts[0];
              final domain = parts[1];
              final maskedLocal = local.length > 2 ? '${local.substring(0, 2)}***' : '***';
              final domainParts = domain.split('.');
              final maskedDomain = domainParts.length > 1 ? '***${domainParts.last}' : '***';
              return '$maskedLocal@$maskedDomain';
            }
            return '***@***.***';
          })
          // Replace UIDs with consistent placeholder
          .replaceAllMapped(_uidPattern, (match) => '***UID***')
          // Replace phone numbers
          .replaceAllMapped(_phonePattern, (match) => '***-***-****')
          // Replace display names
          .replaceAllMapped(_displayNamePattern, (match) => 'displayName: "***"')
          // Replace user references
          .replaceAllMapped(_userIdPattern, (match) => 'userId: ***@***.***')
          // Replace potential sensitive data patterns
          .replaceAllMapped(_sensitiveKeyPattern, (match) => '[SENSITIVE]');
    } catch (e) {
      // If sanitization fails, return a safe placeholder
      return '[SANITIZED_MESSAGE]';
    }
  }
  
  /// Sanitize context map without mutating original
  static Map<String, dynamic> _sanitizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) return {};
    
    final sanitizedContext = <String, dynamic>{};
    
    try {
      context.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        
        // Skip sensitive fields entirely
        if (_sensitiveFields.contains(lowerKey)) {
          sanitizedContext[key] = '[REDACTED]';
          return;
        }
        
        // Sanitize string values
        if (value is String) {
          sanitizedContext[key] = _sanitizePII(value);
        } else if (value is Map) {
          // Recursively sanitize nested maps
          sanitizedContext[key] = _sanitizeContext(Map<String, dynamic>.from(value));
        } else if (value is List) {
          // Sanitize lists
          sanitizedContext[key] = value.map((item) {
            if (item is String) return _sanitizePII(item);
            if (item is Map) return _sanitizeContext(Map<String, dynamic>.from(item));
            return item;
          }).toList();
        } else {
          // Safe conversion for other types
          sanitizedContext[key] = _safeToString(value, maxLength: LogConfig.maxContextLength);
        }
      });
    } catch (e) {
      // If context sanitization fails, return empty context
      return {'context_error': 'Failed to sanitize context'};
    }
    
    return sanitizedContext;
  }
  
  /// Format structured log message with enhanced metadata
  static String _formatMessage(LogLevel level, String category, String message, Map<String, dynamic>? context) {
    try {
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final levelStr = level.name.toUpperCase();
      final sanitizedMessage = _safeToString(_sanitizePII(message));
      
      var formattedMessage = '[$timestamp] [$_tag] [$levelStr] [$category] $sanitizedMessage';
      
      final sanitizedContext = _sanitizeContext(context);
      if (sanitizedContext.isNotEmpty) {
        final contextStr = _safeToString(sanitizedContext, maxLength: LogConfig.maxContextLength);
        formattedMessage += ' | Context: $contextStr';
      }
      
      return formattedMessage;
    } catch (e) {
      // Fallback formatting if main formatting fails
      return '[${DateTime.now().toIso8601String()}] [$_tag] [ERROR] [LOGGER] Failed to format log message: ${e.toString()}';
    }
  }
  
  /// Internal logging method with consistent behavior
  static void _log(LogLevel level, String category, String message, [Map<String, dynamic>? context]) {
    if (!_shouldLog(level)) return;
    
    try {
      final formatted = _formatMessage(level, category, message, context);
      
      // Always use debugPrint for Flutter compatibility
      debugPrint(formatted);
      
      // In production, you could add additional loggers here
      if (_isProduction && (level == LogLevel.error || level == LogLevel.critical)) {
        // TODO: Add crash reporting or analytics logging
        // Example: FirebaseCrashlytics.instance.log(formatted);
      }
    } catch (e) {
      // Last resort logging
      debugPrint('[${DateTime.now()}] [LOGGER_ERROR] Failed to log message: $e');
    }
  }
  
  /// Log debug messages (only in debug mode or if explicitly enabled)
  static void debug(String category, String message, [Map<String, dynamic>? context]) {
    if (_isDebugMode || LogConfig.minLevel == LogLevel.debug) {
      _log(LogLevel.debug, category, message, context);
    }
  }
  
  /// Log informational messages
  static void info(String category, String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.info, category, message, context);
  }
  
  /// Log warning messages
  static void warning(String category, String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.warning, category, message, context);
  }
  
  /// Log error messages with enhanced error handling
  static void error(String category, String message, [Object? error, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    final errorContext = Map<String, dynamic>.from(context ?? {});
    
    if (error != null) {
      try {
        errorContext['error_type'] = error.runtimeType.toString();
        errorContext['error_message'] = _sanitizePII(_safeToString(error));
      } catch (e) {
        errorContext['error_type'] = 'Unknown';
        errorContext['error_message'] = '[Error serialization failed]';
      }
    }
    
    if (stackTrace != null && LogConfig.enableStackTraces) {
      try {
        // Limit stack trace length and sanitize
        final stackString = stackTrace.toString();
        final lines = stackString.split('\n');
        final limitedLines = lines.take(20).join('\n'); // Limit to 20 lines
        errorContext['stack_trace'] = _sanitizePII(limitedLines);
      } catch (e) {
        errorContext['stack_trace'] = '[Stack trace unavailable]';
      }
    }
    
    _log(LogLevel.error, category, message, errorContext);
  }
  
  /// Log critical messages (always logged regardless of level)
  static void critical(String category, String message, [Object? errorObj, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    final originalMinLevel = LogConfig.minLevel;
    LogConfig.minLevel = LogLevel.critical; // Ensure critical logs always pass
    
    try {
      SecureLogger.error(category, '[CRITICAL] $message', errorObj, stackTrace, context);
    } finally {
      LogConfig.minLevel = originalMinLevel; // Restore original level
    }
  }
  
  /// Log authentication events with extra security
  static void authEvent(String event, [Map<String, dynamic>? context]) {
    final sanitizedContext = <String, dynamic>{};
    
    if (context != null) {
      context.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        // Extra strict filtering for auth events
        if (!_sensitiveFields.contains(lowerKey) && 
            !lowerKey.contains('credential') &&
            !lowerKey.contains('login') &&
            !lowerKey.contains('pass')) {
          sanitizedContext[key] = value is String ? _sanitizePII(value) : value;
        }
      });
    }
    
    // Always add auth event marker
    sanitizedContext['event_type'] = 'authentication';
    sanitizedContext['timestamp'] = DateTime.now().toUtc().toIso8601String();
    
    info('AUTH', event, sanitizedContext);
  }
  
  /// Log data operations with comprehensive tracking
  static void dataOperation(String operation, String dataType, bool success, [Map<String, dynamic>? context]) {
    final operationContext = Map<String, dynamic>.from(context ?? {});
    operationContext['operation'] = operation;
    operationContext['data_type'] = dataType;
    operationContext['success'] = success;
    operationContext['timestamp'] = DateTime.now().toUtc().toIso8601String();
    
    if (success) {
      info('DATA', '$operation $dataType completed', operationContext);
    } else {
      warning('DATA', '$operation $dataType failed', operationContext);
    }
  }
  
  /// Log performance metrics with statistical context
  static void performance(String operation, Duration duration, [Map<String, dynamic>? context]) {
    if (!LogConfig.enablePerformanceLogging) return;
    
    final perfContext = Map<String, dynamic>.from(context ?? {});
    perfContext['operation'] = operation;
    perfContext['duration_ms'] = duration.inMilliseconds;
    perfContext['duration_seconds'] = duration.inMilliseconds / 1000.0;
    perfContext['timestamp'] = DateTime.now().toUtc().toIso8601String();
    
    // Add performance classification
    if (duration.inMilliseconds > 5000) {
      perfContext['performance'] = 'slow';
      warning('PERFORMANCE', '$operation took ${duration.inMilliseconds}ms (slow)', perfContext);
    } else if (duration.inMilliseconds > 1000) {
      perfContext['performance'] = 'medium';
      info('PERFORMANCE', '$operation took ${duration.inMilliseconds}ms', perfContext);
    } else {
      perfContext['performance'] = 'fast';
      debug('PERFORMANCE', '$operation took ${duration.inMilliseconds}ms', perfContext);
    }
  }
  
  /// Log user actions with privacy protection
  static void userAction(String action, [Map<String, dynamic>? context]) {
    final actionContext = Map<String, dynamic>.from(context ?? {});
    actionContext['action'] = action;
    actionContext['timestamp'] = DateTime.now().toUtc().toIso8601String();
    actionContext['session_id'] = '***'; // Never log actual session IDs
    
    info('USER_ACTION', action, actionContext);
  }
  
  /// Network request logging with URL sanitization
  static void networkRequest(String method, String url, int statusCode, Duration duration, [Map<String, dynamic>? context]) {
    final networkContext = Map<String, dynamic>.from(context ?? {});
    
    // Sanitize URL to remove sensitive query parameters
    final sanitizedUrl = _sanitizeUrl(url);
    
    networkContext['method'] = method;
    networkContext['url'] = sanitizedUrl;
    networkContext['status_code'] = statusCode;
    networkContext['duration_ms'] = duration.inMilliseconds;
    networkContext['timestamp'] = DateTime.now().toUtc().toIso8601String();
    
    if (statusCode >= 200 && statusCode < 300) {
      info('NETWORK', '$method $sanitizedUrl [$statusCode]', networkContext);
    } else if (statusCode >= 400 && statusCode < 500) {
      warning('NETWORK', '$method $sanitizedUrl [$statusCode] Client Error', networkContext);
    } else if (statusCode >= 500) {
      error('NETWORK', '$method $sanitizedUrl [$statusCode] Server Error', null, null, networkContext);
    } else {
      info('NETWORK', '$method $sanitizedUrl [$statusCode]', networkContext);
    }
  }
  
  /// Sanitize URL to remove sensitive query parameters
  static String _sanitizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final sensitiveParams = ['token', 'key', 'secret', 'password', 'auth', 'api_key', 'access_token'];
      
      final sanitizedParams = <String, String>{};
      uri.queryParameters.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        if (sensitiveParams.any((param) => lowerKey.contains(param))) {
          sanitizedParams[key] = '[REDACTED]';
        } else {
          sanitizedParams[key] = value;
        }
      });
      
      return uri.replace(queryParameters: sanitizedParams.isEmpty ? null : sanitizedParams).toString();
    } catch (e) {
      return '[INVALID_URL]';
    }
  }
  
  /// Utility method to measure and log execution time
  static Future<T> measureAsync<T>(String operation, Future<T> Function() task, [Map<String, dynamic>? context]) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await task();
      stopwatch.stop();
      performance(operation, stopwatch.elapsed, context);
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      error('PERFORMANCE', 'Failed during $operation', e, stackTrace, {
        ...?context,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }
  
  /// Utility method to measure and log synchronous execution time
  static T measure<T>(String operation, T Function() task, [Map<String, dynamic>? context]) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = task();
      stopwatch.stop();
      performance(operation, stopwatch.elapsed, context);
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      error('PERFORMANCE', 'Failed during $operation', e, stackTrace, {
        ...?context,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }
}