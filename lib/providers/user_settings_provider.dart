import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_settings.dart';
import '../widgets/timetable_widget.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/theme_service.dart' as theme_service;

part 'user_settings_provider.freezed.dart';

/// State class for user settings management
@freezed
class UserSettingsState with _$UserSettingsState {
  const factory UserSettingsState({
    UserSettings? userSettings,
    @Default(false) bool isLoading,
    @Default(false) bool isSaving,
    String? error,
  }) = _UserSettingsState;
}

/// User settings service provider for dependency injection
final userSettingsServiceProvider = Provider<UserSettingsNotifier>((ref) {
  return UserSettingsNotifier(
    authService: AuthService(),
    firestoreService: FirestoreService(),
  );
});

/// Main user settings provider
final userSettingsProvider = StateNotifierProvider<UserSettingsNotifier, UserSettingsState>((ref) {
  return ref.watch(userSettingsServiceProvider);
});

/// Convenience providers for specific settings
final themeProvider = Provider<ThemeMode>((ref) {
  final state = ref.watch(userSettingsProvider);
  return state.userSettings?.themeMode ?? ThemeMode.system;
});

final themeVariantProvider = Provider<theme_service.AppTheme>((ref) {
  final state = ref.watch(userSettingsProvider);
  return state.userSettings?.themeVariant ?? theme_service.AppTheme.githubDark;
});

final sortOrderProvider = Provider<TimetableListSortOrder>((ref) {
  final state = ref.watch(userSettingsProvider);
  return state.userSettings?.sortOrder ?? TimetableListSortOrder.dateModifiedDesc;
});

final customTimetableOrderProvider = Provider<List<String>>((ref) {
  final state = ref.watch(userSettingsProvider);
  return state.userSettings?.customTimetableOrder ?? [];
});

/// Provider for timetable-specific settings
final timetableSettingsProvider = Provider.family<TimetableSettings, String>((ref, timetableId) {
  final state = ref.watch(userSettingsProvider);
  return state.userSettings?.getTimetableSettings(timetableId) ?? TimetableSettings.defaultSettings();
});

/// User settings state notifier that manages all user settings operations
class UserSettingsNotifier extends StateNotifier<UserSettingsState> {
  static const String _localStorageKey = 'user_settings';

  final AuthService _authService;
  final FirestoreService _firestoreService;

  UserSettingsNotifier({
    required AuthService authService,
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        super(const UserSettingsState());

  /// Initialize user settings
  Future<void> initializeSettings() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      if (_authService.isAuthenticated) {
        await _loadFromFirestore();
      } else {
        await _loadFromLocalStorage();
      }
    } catch (e) {
      // Fall back to default settings
      final userId = _authService.currentUser?.uid ?? 'guest';
      state = state.copyWith(
        userSettings: UserSettings.defaultSettings(userId),
        error: 'Failed to load settings, using defaults',
      );
    }

    state = state.copyWith(isLoading: false);
  }

  /// Update theme mode
  Future<void> updateThemeMode(ThemeMode themeMode) async {
    await _updateSettings((settings) => settings.copyWith(themeMode: themeMode));
  }

  /// Update theme variant
  Future<void> updateThemeVariant(theme_service.AppTheme themeVariant) async {
    await _updateSettings((settings) => settings.copyWith(themeVariant: themeVariant));
  }

  /// Update timetable list sort order
  Future<void> updateSortOrder(TimetableListSortOrder sortOrder) async {
    await _updateSettings((settings) => settings.copyWith(sortOrder: sortOrder));
  }

  /// Update custom timetable order
  Future<void> updateCustomTimetableOrder(List<String> order) async {
    await _updateSettings((settings) => settings.copyWith(
      customTimetableOrder: order,
      sortOrder: TimetableListSortOrder.custom,
    ));
  }

  /// Update timetable-specific settings
  Future<void> updateTimetableSettings(
    String timetableId,
    TimetableSize? size,
    TimetableLayout? layout,
  ) async {
    final currentSettings = state.userSettings;
    if (currentSettings == null) return;

    final timetableSettings = currentSettings.getTimetableSettings(timetableId);
    final newTimetableSettings = timetableSettings.copyWith(
      size: size,
      layout: layout,
    );

    await _updateSettings((settings) => settings.updateTimetableSettings(timetableId, newTimetableSettings));
  }

  /// Remove timetable settings when timetable is deleted
  Future<void> removeTimetableSettings(String timetableId) async {
    await _updateSettings((settings) => settings.removeTimetableSettings(timetableId));
  }

  /// Clear all settings (useful for logout)
  Future<void> clearSettings() async {
    state = state.copyWith(userSettings: null, error: null);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localStorageKey);
    } catch (e) {
      // Ignore clear errors
    }
  }

  /// Handle user authentication state changes
  Future<void> onAuthStateChanged(bool isAuthenticated, String? userId) async {
    if (isAuthenticated && userId != null) {
      // User logged in - migrate local settings to Firestore if they exist
      final localSettings = state.userSettings;
      await _loadFromFirestore();

      // If we had local settings and no Firestore settings, migrate them
      if (localSettings != null && state.userSettings?.userId == userId) {
        final migratedSettings = localSettings.copyWith(userId: userId);
        state = state.copyWith(userSettings: migratedSettings);
        await _saveToFirestore();
      }
    } else {
      // User logged out - clear and load guest settings
      await clearSettings();
      await _loadFromLocalStorage();
    }
  }

  /// Get timetable settings for specific timetable
  TimetableSettings getTimetableSettings(String timetableId) {
    return state.userSettings?.getTimetableSettings(timetableId) ?? TimetableSettings.defaultSettings();
  }

  /// Get timetable size for specific timetable
  TimetableSize getTimetableSize(String timetableId) {
    return getTimetableSettings(timetableId).size;
  }

  /// Get timetable layout for specific timetable
  TimetableLayout getTimetableLayout(String timetableId) {
    return getTimetableSettings(timetableId).layout;
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Private helper methods

  Future<void> _updateSettings(UserSettings Function(UserSettings) updater) async {
    // Ensure settings are initialized
    if (state.userSettings == null) {
      await initializeSettings();
    }

    final currentSettings = state.userSettings;
    if (currentSettings == null) return;

    final updatedSettings = updater(currentSettings);
    state = state.copyWith(
      userSettings: updatedSettings,
      isSaving: true,
      error: null,
    );

    try {
      if (_authService.isAuthenticated) {
        await _saveToFirestore();
      } else {
        await _saveToLocalStorage();
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to save settings: ${e.toString()}',
      );
    }

    state = state.copyWith(isSaving: false);
  }

  Future<void> _loadFromFirestore() async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;

      final doc = await _firestoreService.getDocument('user-settings', userId);
      if (doc != null && doc.data() != null) {
        final settings = UserSettings.fromJson(doc.data()!);
        state = state.copyWith(userSettings: settings);
      } else {
        // Create default settings
        final settings = UserSettings.defaultSettings(userId);
        state = state.copyWith(userSettings: settings);
        await _saveToFirestore();
      }
    } catch (e) {
      final userId = _authService.currentUser?.uid ?? 'guest';
      state = state.copyWith(
        userSettings: UserSettings.defaultSettings(userId),
        error: 'Failed to load from Firestore: ${e.toString()}',
      );
    }
  }

  Future<void> _loadFromLocalStorage() async {
    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          // Mock values already set or not needed
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_localStorageKey);

      if (settingsJson != null) {
        final settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
        final settings = UserSettings.fromJson(settingsMap);
        state = state.copyWith(userSettings: settings);
      } else {
        // Create default settings
        final settings = UserSettings.defaultSettings('guest');
        state = state.copyWith(userSettings: settings);
        await _saveToLocalStorage();
      }
    } catch (e) {
      state = state.copyWith(
        userSettings: UserSettings.defaultSettings('guest'),
        error: 'Failed to load from local storage: ${e.toString()}',
      );
    }
  }

  Future<void> _saveToFirestore() async {
    final currentSettings = state.userSettings;
    if (currentSettings == null) return;

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;

      final success = await _firestoreService.saveDocument(
        'user-settings',
        userId,
        currentSettings.toJson()
      );
      if (!success) {
        throw Exception('Failed to save to Firestore');
      }
    } catch (e) {
      // Fall back to local storage
      await _saveToLocalStorage();
    }
  }

  Future<void> _saveToLocalStorage() async {
    final currentSettings = state.userSettings;
    if (currentSettings == null) return;

    try {
      if (kIsWeb) {
        try {
          SharedPreferences.setMockInitialValues({});
        } catch (e) {
          // Mock values already set or not needed
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(currentSettings.toJson());
      await prefs.setString(_localStorageKey, settingsJson);
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to save to local storage: ${e.toString()}',
      );
    }
  }
}