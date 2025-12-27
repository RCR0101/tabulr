import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/theme_service.dart' as theme_service;
import '../services/secure_logger.dart';

/// Theme state class
class ThemeState {
  final theme_service.AppTheme currentTheme;
  final ThemeMode themeMode;
  final bool isLoading;
  final String? error;

  const ThemeState({
    required this.currentTheme,
    required this.themeMode,
    this.isLoading = false,
    this.error,
  });

  ThemeState copyWith({
    theme_service.AppTheme? currentTheme,
    ThemeMode? themeMode,
    bool? isLoading,
    String? error,
  }) {
    return ThemeState(
      currentTheme: currentTheme ?? this.currentTheme,
      themeMode: themeMode ?? this.themeMode,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeState &&
          runtimeType == other.runtimeType &&
          currentTheme == other.currentTheme &&
          themeMode == other.themeMode &&
          isLoading == other.isLoading &&
          error == other.error;

  @override
  int get hashCode =>
      currentTheme.hashCode ^
      themeMode.hashCode ^
      isLoading.hashCode ^
      error.hashCode;
}

/// Theme service provider
final themeServiceProvider = Provider<theme_service.ThemeService>((ref) {
  return theme_service.ThemeService();
});

/// Theme state notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier(this._themeService)
      : super(ThemeState(
          currentTheme: _themeService.currentTheme,
          themeMode: _themeService.currentThemeMode,
        )) {
    _initialize();
  }

  final theme_service.ThemeService _themeService;

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await _themeService.initialize();
      
      state = state.copyWith(
        currentTheme: _themeService.currentTheme,
        themeMode: _themeService.currentThemeMode,
        isLoading: false,
        error: null,
      );
      
      SecureLogger.info('THEME', 'Theme service initialized', {
        'current_theme': _themeService.currentTheme.toString(),
        'theme_mode': _themeService.currentThemeMode.toString(),
      });
    } catch (error) {
      SecureLogger.error('THEME', 'Failed to initialize theme service', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to initialize theme',
      );
    }
  }

  /// Set theme variant
  Future<void> setTheme(theme_service.AppTheme theme) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _themeService.setTheme(theme);
      
      state = state.copyWith(
        currentTheme: theme,
        isLoading: false,
      );
      
      SecureLogger.userAction('Theme changed', {'theme': theme.toString()});
    } catch (error) {
      SecureLogger.error('THEME', 'Failed to set theme', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set theme',
      );
    }
  }

  /// Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      await _themeService.setThemeMode(mode);
      
      state = state.copyWith(
        themeMode: mode,
        isLoading: false,
      );
      
      SecureLogger.userAction('Theme mode changed', {'mode': mode.toString()});
    } catch (error) {
      SecureLogger.error('THEME', 'Failed to set theme mode', error);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set theme mode',
      );
    }
  }

  /// Get theme data for current theme
  ThemeData getThemeData() {
    return _themeService.getThemeData(state.currentTheme);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Main theme provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final themeService = ref.watch(themeServiceProvider);
  return ThemeNotifier(themeService);
});

/// Convenience providers
final currentThemeProvider = Provider<theme_service.AppTheme>((ref) {
  return ref.watch(themeProvider).currentTheme;
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeProvider).themeMode;
});

final themeDataProvider = Provider<ThemeData>((ref) {
  final themeNotifier = ref.watch(themeProvider.notifier);
  return themeNotifier.getThemeData();
});

final themeLoadingProvider = Provider<bool>((ref) {
  return ref.watch(themeProvider).isLoading;
});

final themeErrorProvider = Provider<String?>((ref) {
  return ref.watch(themeProvider).error;
});