import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user_settings.dart';
import '../widgets/timetable_widget.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'theme_service.dart' as theme_service;

class UserSettingsService extends ChangeNotifier {
  static const String _localStorageKey = 'user_settings';
  
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  
  UserSettings? _userSettings;
  bool _isLoading = false;

  UserSettings? get userSettings => _userSettings;
  bool get isLoading => _isLoading;

  // Initialize user settings
  Future<void> initializeSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_authService.isAuthenticated) {
        // Load from Firestore
        await _loadFromFirestore();
      } else {
        // Load from local storage
        await _loadFromLocalStorage();
      }
    } catch (e) {
      print('Error initializing user settings: $e');
      // Fall back to default settings
      _userSettings = UserSettings.defaultSettings(_authService.currentUser?.uid ?? 'guest');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load settings from Firestore
  Future<void> _loadFromFirestore() async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;

      final doc = await _firestoreService.getDocument('user-settings', userId);
      if (doc != null && doc.data() != null) {
        _userSettings = UserSettings.fromJson(doc.data()!);
      } else {
        // Create default settings
        _userSettings = UserSettings.defaultSettings(userId);
        await _saveToFirestore();
      }
    } catch (e) {
      print('Error loading settings from Firestore: $e');
      _userSettings = UserSettings.defaultSettings(_authService.currentUser?.uid ?? 'guest');
    }
  }

  // Load settings from local storage
  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_localStorageKey);
      
      if (settingsJson != null) {
        final settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
        _userSettings = UserSettings.fromJson(settingsMap);
      } else {
        // Create default settings
        _userSettings = UserSettings.defaultSettings('guest');
        await _saveToLocalStorage();
      }
    } catch (e) {
      print('Error loading settings from local storage: $e');
      _userSettings = UserSettings.defaultSettings('guest');
    }
  }

  // Save settings to Firestore
  Future<void> _saveToFirestore() async {
    if (_userSettings == null) return;

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;

      final success = await _firestoreService.saveDocument(
        'user-settings', 
        userId, 
        _userSettings!.toJson()
      );
      if (!success) {
        throw Exception('Failed to save to Firestore');
      }
    } catch (e) {
      print('Error saving settings to Firestore: $e');
      // Fall back to local storage
      await _saveToLocalStorage();
    }
  }

  // Save settings to local storage
  Future<void> _saveToLocalStorage() async {
    if (_userSettings == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(_userSettings!.toJson());
      await prefs.setString(_localStorageKey, settingsJson);
    } catch (e) {
      print('Error saving settings to local storage: $e');
    }
  }

  // Update theme mode
  Future<void> updateThemeMode(ThemeMode themeMode) async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(themeMode: themeMode);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Update theme variant
  Future<void> updateThemeVariant(theme_service.AppTheme themeVariant) async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(themeVariant: themeVariant);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Update timetable list sort order
  Future<void> updateSortOrder(TimetableListSortOrder sortOrder) async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(sortOrder: sortOrder);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Update custom timetable order
  Future<void> updateCustomTimetableOrder(List<String> order) async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) return;

    _userSettings = _userSettings!.copyWith(
      customTimetableOrder: order,
      sortOrder: TimetableListSortOrder.custom,
    );
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Update dont show bottom disclaimer setting
  Future<void> updateDontShowBottomDisclaimer(bool dontShow) async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(dontShowBottomDisclaimer: dontShow);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Reset disclaimer setting (useful for testing)
  Future<void> resetDisclaimerSetting() async {
    await updateDontShowBottomDisclaimer(false);
  }

  // Update dont show top announcement setting
  Future<void> updateDontShowTopUpdated() async {
    // Ensure settings are initialized
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(dontShowTopUpdated: DateTime.now());
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Reset top announcement setting (useful for testing)
  Future<void> resetTopAnnouncementSetting() async {
    if (_userSettings == null) {
      await initializeSettings();
    }
    
    if (_userSettings == null) {
      print('Warning: Failed to initialize user settings');
      return;
    }

    _userSettings = _userSettings!.copyWith(dontShowTopUpdated: null);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Update timetable-specific settings
  Future<void> updateTimetableSettings(
    String timetableId,
    TimetableSize? size,
    TimetableLayout? layout,
  ) async {
    if (_userSettings == null) return;

    final currentSettings = _userSettings!.getTimetableSettings(timetableId);
    final newSettings = currentSettings.copyWith(
      size: size,
      layout: layout,
    );

    _userSettings = _userSettings!.updateTimetableSettings(timetableId, newSettings);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Remove timetable settings when timetable is deleted
  Future<void> removeTimetableSettings(String timetableId) async {
    if (_userSettings == null) return;

    _userSettings = _userSettings!.removeTimetableSettings(timetableId);
    notifyListeners();

    if (_authService.isAuthenticated) {
      await _saveToFirestore();
    } else {
      await _saveToLocalStorage();
    }
  }

  // Get theme mode
  ThemeMode get themeMode => _userSettings?.themeMode ?? ThemeMode.system;

  // Get theme variant
  theme_service.AppTheme get themeVariant => _userSettings?.themeVariant ?? theme_service.AppTheme.githubDark;

  // Get sort order
  TimetableListSortOrder get sortOrder => _userSettings?.sortOrder ?? TimetableListSortOrder.dateModifiedDesc;

  // Get custom timetable order
  List<String> get customTimetableOrder => _userSettings?.customTimetableOrder ?? [];
  
  // Get dont show bottom disclaimer setting
  bool get dontShowBottomDisclaimer => _userSettings?.dontShowBottomDisclaimer ?? false;
  
  // Get dont show top announcement dismissal time
  DateTime? get dontShowTopUpdated => _userSettings?.dontShowTopUpdated;

  // Get timetable settings
  TimetableSettings getTimetableSettings(String timetableId) {
    return _userSettings?.getTimetableSettings(timetableId) ?? TimetableSettings.defaultSettings();
  }

  // Get timetable size for specific timetable
  TimetableSize getTimetableSize(String timetableId) {
    return getTimetableSettings(timetableId).size;
  }

  // Get timetable layout for specific timetable
  TimetableLayout getTimetableLayout(String timetableId) {
    return getTimetableSettings(timetableId).layout;
  }

  // Migrate from old preferences service if needed
  Future<void> migrateFromOldPreferences() async {
    // This can be implemented to migrate existing preferences
    // from the old PreferencesService to the new UserSettingsService
    print('Migration from old preferences not implemented yet');
  }

  // Clear all settings (useful for logout)
  Future<void> clearSettings() async {
    _userSettings = null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localStorageKey);
    } catch (e) {
      print('Error clearing local settings: $e');
    }
    
    notifyListeners();
  }

  // Handle user authentication state changes
  Future<void> onAuthStateChanged(bool isAuthenticated, String? userId) async {
    if (isAuthenticated && userId != null) {
      // User logged in - migrate local settings to Firestore if they exist
      final localSettings = _userSettings;
      await _loadFromFirestore();
      
      // If we had local settings and no Firestore settings, migrate them
      if (localSettings != null && _userSettings?.userId == userId) {
        _userSettings = localSettings.copyWith(userId: userId);
        await _saveToFirestore();
      }
    } else {
      // User logged out - clear and load guest settings
      await clearSettings();
      await _loadFromLocalStorage();
    }
  }
}