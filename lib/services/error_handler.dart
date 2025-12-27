import 'package:flutter/material.dart';
import 'secure_logger.dart';
import 'dialog_service.dart';

/// Exception types for better error categorization
enum ErrorType {
  network,
  authentication,
  validation,
  storage,
  parsing,
  unknown,
}

/// Custom exception class for app-specific errors
class AppException implements Exception {
  final String message;
  final ErrorType type;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;

  const AppException({
    required this.message,
    required this.type,
    this.originalError,
    this.stackTrace,
    this.context,
  });

  @override
  String toString() => 'AppException: $message';
}

/// Network-specific exceptions
class NetworkException extends AppException {
  const NetworkException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) : super(
          message: message,
          type: ErrorType.network,
          originalError: originalError,
          stackTrace: stackTrace,
          context: context,
        );
}

/// Authentication-specific exceptions
class AuthException extends AppException {
  const AuthException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) : super(
          message: message,
          type: ErrorType.authentication,
          originalError: originalError,
          stackTrace: stackTrace,
          context: context,
        );
}

/// Validation-specific exceptions
class ValidationException extends AppException {
  const ValidationException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) : super(
          message: message,
          type: ErrorType.validation,
          originalError: originalError,
          stackTrace: stackTrace,
          context: context,
        );
}

/// Storage-specific exceptions
class StorageException extends AppException {
  const StorageException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) : super(
          message: message,
          type: ErrorType.storage,
          originalError: originalError,
          stackTrace: stackTrace,
          context: context,
        );
}

/// Parsing-specific exceptions
class ParsingException extends AppException {
  const ParsingException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) : super(
          message: message,
          type: ErrorType.parsing,
          originalError: originalError,
          stackTrace: stackTrace,
          context: context,
        );
}

/// Centralized error handling service
class ErrorHandler {
  static const Map<ErrorType, String> _defaultUserMessages = {
    ErrorType.network: 'Network error. Please check your connection and try again.',
    ErrorType.authentication: 'Authentication failed. Please sign in again.',
    ErrorType.validation: 'Please check your input and try again.',
    ErrorType.storage: 'Storage error. Please try again.',
    ErrorType.parsing: 'Data processing error. Please try again.',
    ErrorType.unknown: 'An unexpected error occurred. Please try again.',
  };

  static const Map<ErrorType, String> _logCategories = {
    ErrorType.network: 'NETWORK',
    ErrorType.authentication: 'AUTH',
    ErrorType.validation: 'VALIDATION',
    ErrorType.storage: 'STORAGE',
    ErrorType.parsing: 'PARSE',
    ErrorType.unknown: 'ERROR',
  };

  /// Handle an error with logging and optional user notification
  static Future<void> handleError({
    required dynamic error,
    StackTrace? stackTrace,
    String? customMessage,
    Map<String, dynamic>? context,
    BuildContext? uiContext,
    bool showToUser = true,
    String? operation,
  }) async {
    final appError = _processError(error, stackTrace, context);
    
    // Log the error
    await _logError(appError, operation, context);
    
    // Show to user if requested
    if (showToUser && uiContext != null) {
      await _showErrorToUser(
        context: uiContext,
        error: appError,
        customMessage: customMessage,
      );
    }
  }

  /// Create a standardized AppException from any error
  static AppException _processError(
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ) {
    if (error is AppException) {
      return error;
    }

    // Analyze error type based on error content
    final errorString = error.toString().toLowerCase();
    
    ErrorType type = ErrorType.unknown;
    String message = error.toString();

    if (errorString.contains('network') || 
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      type = ErrorType.network;
    } else if (errorString.contains('auth') || 
               errorString.contains('permission') ||
               errorString.contains('unauthorized')) {
      type = ErrorType.authentication;
    } else if (errorString.contains('validation') || 
               errorString.contains('invalid') ||
               errorString.contains('required')) {
      type = ErrorType.validation;
    } else if (errorString.contains('storage') || 
               errorString.contains('database') ||
               errorString.contains('firestore')) {
      type = ErrorType.storage;
    } else if (errorString.contains('parse') || 
               errorString.contains('format') ||
               errorString.contains('json')) {
      type = ErrorType.parsing;
    }

    return AppException(
      message: message,
      type: type,
      originalError: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Log error using SecureLogger
  static Future<void> _logError(
    AppException error,
    String? operation,
    Map<String, dynamic>? additionalContext,
  ) async {
    final category = _logCategories[error.type] ?? 'ERROR';
    final logContext = <String, dynamic>{
      'error_type': error.type.toString(),
      'operation': operation ?? 'unknown',
      ...?error.context,
      ...?additionalContext,
    };

    SecureLogger.error(
      category,
      error.message,
      error.originalError,
      error.stackTrace,
      logContext,
    );
  }

  /// Show error to user via dialog
  static Future<void> _showErrorToUser({
    required BuildContext context,
    required AppException error,
    String? customMessage,
  }) async {
    final userMessage = customMessage ?? 
                       _defaultUserMessages[error.type] ?? 
                       error.message;

    await DialogService.showErrorDialog(
      context: context,
      title: _getErrorTitle(error.type),
      message: userMessage,
    );
  }

  /// Get appropriate error title based on type
  static String _getErrorTitle(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return 'Connection Error';
      case ErrorType.authentication:
        return 'Authentication Error';
      case ErrorType.validation:
        return 'Validation Error';
      case ErrorType.storage:
        return 'Storage Error';
      case ErrorType.parsing:
        return 'Data Error';
      case ErrorType.unknown:
        return 'Error';
    }
  }

  /// Wrap async operations with error handling
  static Future<T?> handleAsyncOperation<T>({
    required Future<T> Function() operation,
    required String operationName,
    BuildContext? context,
    String? customErrorMessage,
    Map<String, dynamic>? additionalContext,
    bool showErrorToUser = true,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      await handleError(
        error: error,
        stackTrace: stackTrace,
        customMessage: customErrorMessage,
        context: additionalContext,
        uiContext: context,
        showToUser: showErrorToUser,
        operation: operationName,
      );
      return null;
    }
  }

  /// Wrap sync operations with error handling
  static T? handleSyncOperation<T>({
    required T Function() operation,
    required String operationName,
    BuildContext? context,
    String? customErrorMessage,
    Map<String, dynamic>? additionalContext,
    bool showErrorToUser = true,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      handleError(
        error: error,
        stackTrace: stackTrace,
        customMessage: customErrorMessage,
        context: additionalContext,
        uiContext: context,
        showToUser: showErrorToUser,
        operation: operationName,
      );
      return null;
    }
  }

  /// Create specific exception types
  static NetworkException networkError(String message, [dynamic originalError, StackTrace? stackTrace]) {
    return NetworkException(
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  static AuthException authError(String message, [dynamic originalError, StackTrace? stackTrace]) {
    return AuthException(
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  static ValidationException validationError(String message, [dynamic originalError, StackTrace? stackTrace]) {
    return ValidationException(
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  static StorageException storageError(String message, [dynamic originalError, StackTrace? stackTrace]) {
    return StorageException(
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  static ParsingException parsingError(String message, [dynamic originalError, StackTrace? stackTrace]) {
    return ParsingException(
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}