import '../widgets/timetable_widget.dart';
import '../services/theme_service.dart' as theme_service;
import 'package:cloud_firestore/cloud_firestore.dart';

// Helper function to parse DateTime from both String and Firestore Timestamp
DateTime _parseDateTime(dynamic value) {
  if (value == null) {
    return DateTime.now();
  } else if (value is String) {
    return DateTime.parse(value);
  } else if (value is Timestamp) {
    return value.toDate();
  } else {
    return DateTime.now();
  }
}

enum ThemeMode { light, dark, system }

enum TimetableListSortOrder {
  dateCreatedDesc,
  dateCreatedAsc,
  dateModifiedDesc,
  dateModifiedAsc,
  alphabeticalAsc,
  alphabeticalDesc,
  custom
}

class TimetableSettings {
  final TimetableSize size;
  final TimetableLayout layout;

  const TimetableSettings({
    required this.size,
    required this.layout,
  });

  Map<String, dynamic> toJson() {
    return {
      'size': size.toString(),
      'layout': layout.toString(),
    };
  }

  factory TimetableSettings.fromJson(Map<String, dynamic> json) {
    return TimetableSettings(
      size: TimetableSize.values.firstWhere(
        (e) => e.toString() == json['size'],
        orElse: () => TimetableSize.medium,
      ),
      layout: TimetableLayout.values.firstWhere(
        (e) => e.toString() == json['layout'],
        orElse: () => TimetableLayout.vertical,
      ),
    );
  }

  factory TimetableSettings.defaultSettings() {
    return const TimetableSettings(
      size: TimetableSize.medium,
      layout: TimetableLayout.vertical,
    );
  }

  TimetableSettings copyWith({
    TimetableSize? size,
    TimetableLayout? layout,
  }) {
    return TimetableSettings(
      size: size ?? this.size,
      layout: layout ?? this.layout,
    );
  }
}

class UserSettings {
  final String userId;
  final ThemeMode themeMode;
  final theme_service.AppTheme themeVariant;
  final TimetableListSortOrder sortOrder;
  final Map<String, TimetableSettings> timetableSettings; // timetableId -> settings
  final List<String> customTimetableOrder; // for custom sorting
  final bool dontShowBottomDisclaimer; // whether to hide the bottom disclaimer permanently
  final DateTime? dontShowTopUpdated; // when the user last dismissed the top announcement
  final DateTime lastUpdated;

  const UserSettings({
    required this.userId,
    required this.themeMode,
    required this.themeVariant,
    required this.sortOrder,
    required this.timetableSettings,
    required this.customTimetableOrder,
    this.dontShowBottomDisclaimer = false,
    this.dontShowTopUpdated,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'themeMode': themeMode.toString(),
      'themeVariant': themeVariant.toString(),
      'sortOrder': sortOrder.toString(),
      'timetableSettings': timetableSettings.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'customTimetableOrder': customTimetableOrder,
      'dontShowBottomDisclaimer': dontShowBottomDisclaimer,
      'dontShowTopUpdated': dontShowTopUpdated?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['userId'] ?? '',
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.toString() == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      themeVariant: theme_service.AppTheme.values.firstWhere(
        (e) => e.toString() == json['themeVariant'],
        orElse: () => theme_service.AppTheme.githubDark,
      ),
      sortOrder: TimetableListSortOrder.values.firstWhere(
        (e) => e.toString() == json['sortOrder'],
        orElse: () => TimetableListSortOrder.dateModifiedDesc,
      ),
      timetableSettings: (json['timetableSettings'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(
                key,
                TimetableSettings.fromJson(value as Map<String, dynamic>),
              )),
      customTimetableOrder: List<String>.from(json['customTimetableOrder'] ?? []),
      dontShowBottomDisclaimer: json['dontShowBottomDisclaimer'] ?? false,
      dontShowTopUpdated: json['dontShowTopUpdated'] != null ? _parseDateTime(json['dontShowTopUpdated']) : null,
      lastUpdated: _parseDateTime(json['lastUpdated']),
    );
  }

  factory UserSettings.defaultSettings(String userId) {
    return UserSettings(
      userId: userId,
      themeMode: ThemeMode.system,
      themeVariant: theme_service.AppTheme.githubDark,
      sortOrder: TimetableListSortOrder.dateModifiedDesc,
      timetableSettings: {},
      customTimetableOrder: [],
      dontShowBottomDisclaimer: false,
      dontShowTopUpdated: null,
      lastUpdated: DateTime.now(),
    );
  }

  UserSettings copyWith({
    String? userId,
    ThemeMode? themeMode,
    theme_service.AppTheme? themeVariant,
    TimetableListSortOrder? sortOrder,
    Map<String, TimetableSettings>? timetableSettings,
    List<String>? customTimetableOrder,
    bool? dontShowBottomDisclaimer,
    DateTime? dontShowTopUpdated,
    DateTime? lastUpdated,
  }) {
    return UserSettings(
      userId: userId ?? this.userId,
      themeMode: themeMode ?? this.themeMode,
      themeVariant: themeVariant ?? this.themeVariant,
      sortOrder: sortOrder ?? this.sortOrder,
      timetableSettings: timetableSettings ?? this.timetableSettings,
      customTimetableOrder: customTimetableOrder ?? this.customTimetableOrder,
      dontShowBottomDisclaimer: dontShowBottomDisclaimer ?? this.dontShowBottomDisclaimer,
      dontShowTopUpdated: dontShowTopUpdated ?? this.dontShowTopUpdated,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  TimetableSettings getTimetableSettings(String timetableId) {
    return timetableSettings[timetableId] ?? TimetableSettings.defaultSettings();
  }

  UserSettings updateTimetableSettings(String timetableId, TimetableSettings settings) {
    final newTimetableSettings = Map<String, TimetableSettings>.from(timetableSettings);
    newTimetableSettings[timetableId] = settings;
    
    return copyWith(
      timetableSettings: newTimetableSettings,
      lastUpdated: DateTime.now(),
    );
  }

  UserSettings removeTimetableSettings(String timetableId) {
    final newTimetableSettings = Map<String, TimetableSettings>.from(timetableSettings);
    newTimetableSettings.remove(timetableId);
    
    final newCustomOrder = List<String>.from(customTimetableOrder);
    newCustomOrder.remove(timetableId);
    
    return copyWith(
      timetableSettings: newTimetableSettings,
      customTimetableOrder: newCustomOrder,
      lastUpdated: DateTime.now(),
    );
  }
}