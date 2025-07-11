import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/timetable.dart';
import '../models/normalized_timetable.dart';
import '../services/incremental_timetable_service.dart';
import '../services/timetable_service.dart';

/// Utility class for migrating from legacy timetable format to normalized format
class MigrationHelper {
  static const String _migrationVersionKey = 'migration_version';
  static const String _currentMigrationVersion = '1.0.0';
  static const String _legacyTimetableKey = 'user_timetable_data';
  static const String _legacyTimetableListKey = 'user_timetables_list';

  /// Check if migration is needed
  static Future<bool> needsMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getString(_migrationVersionKey);
    
    if (currentVersion == _currentMigrationVersion) {
      return false;
    }
    
    // Check if there's legacy data to migrate
    final hasLegacyData = prefs.containsKey(_legacyTimetableKey) ||
                          prefs.containsKey(_legacyTimetableListKey);
    
    return hasLegacyData;
  }

  /// Perform migration from legacy format to normalized format
  static Future<MigrationResult> performMigration() async {
    final result = MigrationResult();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final incrementalService = IncrementalTimetableService();
      
      // Migrate single timetable (legacy format)
      await _migrateSingleTimetable(prefs, incrementalService, result);
      
      // Migrate multiple timetables (if exists)
      await _migrateMultipleTimetables(prefs, incrementalService, result);
      
      // Mark migration as complete
      await prefs.setString(_migrationVersionKey, _currentMigrationVersion);
      
      result.success = true;
      result.message = 'Migration completed successfully';
      
    } catch (e) {
      result.success = false;
      result.message = 'Migration failed: $e';
      result.error = e.toString();
    }
    
    return result;
  }

  /// Migrate single legacy timetable
  static Future<void> _migrateSingleTimetable(
    SharedPreferences prefs,
    IncrementalTimetableService incrementalService,
    MigrationResult result,
  ) async {
    final legacyDataString = prefs.getString(_legacyTimetableKey);
    if (legacyDataString == null) return;
    
    try {
      final legacyData = json.decode(legacyDataString);
      final legacyTimetable = Timetable.fromJson(legacyData);
      
      // Convert to normalized format
      final normalized = await incrementalService.migrateFromLegacy(legacyTimetable);
      
      // Save in new format
      await incrementalService.saveTimetable(normalized, null);
      
      // Remove legacy data
      await prefs.remove(_legacyTimetableKey);
      
      result.migratedTimetables.add(normalized);
      
    } catch (e) {
      result.errors.add('Failed to migrate single timetable: $e');
    }
  }

  /// Migrate multiple legacy timetables
  static Future<void> _migrateMultipleTimetables(
    SharedPreferences prefs,
    IncrementalTimetableService incrementalService,
    MigrationResult result,
  ) async {
    final legacyTimetableIds = prefs.getStringList(_legacyTimetableListKey);
    if (legacyTimetableIds == null) return;
    
    for (final timetableId in legacyTimetableIds) {
      try {
        final legacyKey = 'timetable_$timetableId';
        final legacyDataString = prefs.getString(legacyKey);
        
        if (legacyDataString != null) {
          final legacyData = json.decode(legacyDataString);
          final legacyTimetable = Timetable.fromJson(legacyData);
          
          // Convert to normalized format
          final normalized = await incrementalService.migrateFromLegacy(legacyTimetable);
          
          // Save in new format
          await incrementalService.saveTimetable(normalized, null);
          
          // Remove legacy data
          await prefs.remove(legacyKey);
          
          result.migratedTimetables.add(normalized);
        }
      } catch (e) {
        result.errors.add('Failed to migrate timetable $timetableId: $e');
      }
    }
    
    // Remove legacy timetable list
    await prefs.remove(_legacyTimetableListKey);
  }

  /// Create backup of legacy data before migration
  static Future<void> createBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Backup single timetable
    final legacyData = prefs.getString(_legacyTimetableKey);
    if (legacyData != null) {
      await prefs.setString('backup_${timestamp}_single', legacyData);
    }
    
    // Backup multiple timetables
    final legacyTimetableIds = prefs.getStringList(_legacyTimetableListKey);
    if (legacyTimetableIds != null) {
      await prefs.setStringList('backup_${timestamp}_list', legacyTimetableIds);
      
      for (final timetableId in legacyTimetableIds) {
        final legacyKey = 'timetable_$timetableId';
        final legacyDataString = prefs.getString(legacyKey);
        if (legacyDataString != null) {
          await prefs.setString('backup_${timestamp}_$timetableId', legacyDataString);
        }
      }
    }
  }

  /// Restore from backup (in case migration fails)
  static Future<void> restoreFromBackup(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Restore single timetable
    final backupSingle = prefs.getString('backup_${timestamp}_single');
    if (backupSingle != null) {
      await prefs.setString(_legacyTimetableKey, backupSingle);
    }
    
    // Restore multiple timetables
    final backupList = prefs.getStringList('backup_${timestamp}_list');
    if (backupList != null) {
      await prefs.setStringList(_legacyTimetableListKey, backupList);
      
      for (final timetableId in backupList) {
        final backupData = prefs.getString('backup_${timestamp}_$timetableId');
        if (backupData != null) {
          await prefs.setString('timetable_$timetableId', backupData);
        }
      }
    }
  }

  /// Get migration statistics
  static Future<MigrationStats> getMigrationStats() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = MigrationStats();
    
    // Check current version
    stats.currentVersion = prefs.getString(_migrationVersionKey);
    stats.isLatestVersion = stats.currentVersion == _currentMigrationVersion;
    
    // Count legacy data
    if (prefs.containsKey(_legacyTimetableKey)) {
      stats.legacyTimetablesCount++;
    }
    
    final legacyTimetableIds = prefs.getStringList(_legacyTimetableListKey);
    if (legacyTimetableIds != null) {
      stats.legacyTimetablesCount += legacyTimetableIds.length;
    }
    
    // Count normalized data
    final normalizedIds = prefs.getStringList('user_timetables_list');
    if (normalizedIds != null) {
      stats.normalizedTimetablesCount = normalizedIds.length;
    }
    
    return stats;
  }
}

/// Result of migration operation
class MigrationResult {
  bool success = false;
  String message = '';
  String? error;
  List<NormalizedTimetable> migratedTimetables = [];
  List<String> errors = [];
  
  int get migratedCount => migratedTimetables.length;
  bool get hasErrors => errors.isNotEmpty;
}

/// Statistics about migration status
class MigrationStats {
  String? currentVersion;
  bool isLatestVersion = false;
  int legacyTimetablesCount = 0;
  int normalizedTimetablesCount = 0;
  
  bool get needsMigration => legacyTimetablesCount > 0 && !isLatestVersion;
}

/// Migration progress callback
typedef MigrationProgressCallback = void Function(
  int completed,
  int total,
  String currentItem,
);

/// Enhanced migration with progress tracking
class EnhancedMigrationHelper {
  static Future<MigrationResult> performMigrationWithProgress(
    MigrationProgressCallback? onProgress,
  ) async {
    final result = MigrationResult();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final incrementalService = IncrementalTimetableService();
      
      // Count total items to migrate
      int totalItems = 0;
      if (prefs.containsKey(MigrationHelper._legacyTimetableKey)) totalItems++;
      
      final legacyTimetableIds = prefs.getStringList(MigrationHelper._legacyTimetableListKey);
      if (legacyTimetableIds != null) totalItems += legacyTimetableIds.length;
      
      int completedItems = 0;
      
      // Migrate single timetable
      if (prefs.containsKey(MigrationHelper._legacyTimetableKey)) {
        onProgress?.call(completedItems, totalItems, 'Main timetable');
        
        final legacyDataString = prefs.getString(MigrationHelper._legacyTimetableKey);
        if (legacyDataString != null) {
          final legacyData = json.decode(legacyDataString);
          final legacyTimetable = Timetable.fromJson(legacyData);
          final normalized = await incrementalService.migrateFromLegacy(legacyTimetable);
          await incrementalService.saveTimetable(normalized, null);
          await prefs.remove(MigrationHelper._legacyTimetableKey);
          result.migratedTimetables.add(normalized);
        }
        
        completedItems++;
      }
      
      // Migrate multiple timetables
      if (legacyTimetableIds != null) {
        for (final timetableId in legacyTimetableIds) {
          onProgress?.call(completedItems, totalItems, 'Timetable $timetableId');
          
          try {
            final legacyKey = 'timetable_$timetableId';
            final legacyDataString = prefs.getString(legacyKey);
            
            if (legacyDataString != null) {
              final legacyData = json.decode(legacyDataString);
              final legacyTimetable = Timetable.fromJson(legacyData);
              final normalized = await incrementalService.migrateFromLegacy(legacyTimetable);
              await incrementalService.saveTimetable(normalized, null);
              await prefs.remove(legacyKey);
              result.migratedTimetables.add(normalized);
            }
          } catch (e) {
            result.errors.add('Failed to migrate timetable $timetableId: $e');
          }
          
          completedItems++;
        }
        
        await prefs.remove(MigrationHelper._legacyTimetableListKey);
      }
      
      // Mark migration as complete
      await prefs.setString(MigrationHelper._migrationVersionKey, MigrationHelper._currentMigrationVersion);
      
      result.success = true;
      result.message = 'Migration completed successfully';
      
    } catch (e) {
      result.success = false;
      result.message = 'Migration failed: $e';
      result.error = e.toString();
    }
    
    return result;
  }
}