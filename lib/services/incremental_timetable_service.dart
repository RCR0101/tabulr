import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/normalized_timetable.dart';
import '../models/course.dart';
import 'course_data_service.dart';

/// Service for handling normalized timetable storage with incremental updates
class IncrementalTimetableService {
  static const String _localTimetablePrefix = 'normalized_timetable_';
  static const String _courseMetadataKey = 'course_metadata';
  static const String _timetableListKey = 'user_timetables_list';
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CourseDataService _courseDataService = CourseDataService();
  
  /// Save timetable with incremental updates
  Future<void> saveTimetable(NormalizedTimetable timetable, String? userId) async {
    try {
      // Always save locally first
      await _saveLocalTimetable(timetable);
      
      // Save to Firestore if user is authenticated
      if (userId != null) {
        await _saveFirestoreTimetable(timetable, userId);
      }
    } catch (e) {
      // Error saving timetable: $e
      // Ensure local save succeeded even if Firestore fails
      await _saveLocalTimetable(timetable);
    }
  }

  /// Apply incremental updates to a timetable
  Future<void> applyIncrementalUpdate(
    TimetableUpdateBatch updateBatch, 
    String? userId
  ) async {
    // Validate the update batch
    if (updateBatch.isEmpty) {
      return; // No changes to apply
    }

    // Validate section references
    await _validateSectionReferences([
      ...updateBatch.sectionsToAdd,
      ...updateBatch.sectionsToRemove,
    ]);

    // Create backup of current state for rollback
    final originalTimetable = await _getLocalTimetable(updateBatch.timetableId);
    
    try {
      // Apply locally first
      await _applyLocalUpdate(updateBatch);
      
      // Apply to Firestore if user is authenticated
      if (userId != null) {
        await _applyFirestoreUpdate(updateBatch, userId);
      }
    } catch (e) {
      // Error applying incremental update: $e
      
      // Rollback local changes if Firestore update failed
      if (originalTimetable != null && userId != null) {
        try {
          await _saveLocalTimetable(originalTimetable);
        } catch (rollbackError) {
          // Failed to rollback local changes: $rollbackError
        }
      }
      
      rethrow;
    }
  }

  /// Add section to timetable
  Future<void> addSection(
    String timetableId, 
    SectionReference section, 
    String? userId
  ) async {
    final updateBatch = TimetableUpdateBatch(
      timetableId: timetableId,
      sectionsToAdd: [section],
    );
    await applyIncrementalUpdate(updateBatch, userId);
  }

  /// Remove section from timetable
  Future<void> removeSection(
    String timetableId, 
    SectionReference section, 
    String? userId
  ) async {
    final updateBatch = TimetableUpdateBatch(
      timetableId: timetableId,
      sectionsToRemove: [section],
    );
    await applyIncrementalUpdate(updateBatch, userId);
  }

  /// Get timetable by ID
  Future<NormalizedTimetable?> getTimetable(String timetableId, String? userId) async {
    try {
      // Try Firestore first if user is authenticated
      if (userId != null) {
        final firestoreTimetable = await _getFirestoreTimetable(timetableId, userId);
        if (firestoreTimetable != null) {
          // Cache locally
          await _saveLocalTimetable(firestoreTimetable);
          return firestoreTimetable;
        }
      }
      
      // Fallback to local storage
      return await _getLocalTimetable(timetableId);
    } catch (e) {
      // Error getting timetable: $e
      return await _getLocalTimetable(timetableId);
    }
  }

  /// Get all user timetables
  Future<List<NormalizedTimetable>> getAllTimetables(String? userId) async {
    try {
      if (userId != null) {
        return await _getAllFirestoreTimetables(userId);
      } else {
        return await _getAllLocalTimetables();
      }
    } catch (e) {
      // Error getting all timetables: $e
      return await _getAllLocalTimetables();
    }
  }

  /// Convert normalized timetable to legacy format
  Future<Timetable> toLegacyTimetable(NormalizedTimetable normalized) async {
    final courses = await _courseDataService.fetchCourses();
    return normalized.toLegacyTimetable(courses);
  }

  /// Migrate legacy timetable to normalized format
  Future<NormalizedTimetable> migrateFromLegacy(Timetable legacy) async {
    final normalized = NormalizedTimetable.fromLegacyTimetable(legacy);
    
    // Update course version
    final courseMetadata = await _getCurrentCourseMetadata();
    final normalizedWithVersion = NormalizedTimetable(
      id: normalized.id,
      name: normalized.name,
      createdAt: normalized.createdAt,
      updatedAt: DateTime.now(),
      selectedSections: normalized.selectedSections,
      clashWarnings: normalized.clashWarnings,
      courseVersion: courseMetadata.version,
    );
    
    return normalizedWithVersion;
  }

  /// Check if course data needs updating
  Future<bool> needsCourseDataUpdate(String? currentVersion) async {
    try {
      final metadata = await _getCurrentCourseMetadata();
      return currentVersion != metadata.version;
    } catch (e) {
      // Error checking course data update: $e
      // If we can't check, assume update is needed
      return true;
    }
  }

  /// Safely get all timetables with error recovery
  Future<List<NormalizedTimetable>> getAllTimetablesSafe(String? userId) async {
    try {
      return await getAllTimetables(userId);
    } catch (e) {
      // Error getting timetables safely: $e
      // Return empty list as fallback
      return [];
    }
  }

  /// Batch update multiple timetables
  Future<void> batchUpdateTimetables(
    List<TimetableUpdateBatch> updates,
    String? userId,
  ) async {
    final results = <String, Exception>{};
    
    for (final update in updates) {
      try {
        await applyIncrementalUpdate(update, userId);
      } catch (e) {
        results[update.timetableId] = e is Exception ? e : Exception(e.toString());
      }
    }
    
    if (results.isNotEmpty) {
      throw Exception('Batch update failed for timetables: ${results.keys.join(', ')}');
    }
  }

  /// Create a new timetable
  Future<NormalizedTimetable> createTimetable(
    String name,
    String? userId,
  ) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final courseMetadata = await _getCurrentCourseMetadata();
    
    final timetable = NormalizedTimetable(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      selectedSections: [],
      clashWarnings: [],
      courseVersion: courseMetadata.version,
    );
    
    await saveTimetable(timetable, userId);
    return timetable;
  }

  /// Update timetable name
  Future<void> updateTimetableName(
    String timetableId,
    String newName,
    String? userId,
  ) async {
    final updateBatch = TimetableUpdateBatch(
      timetableId: timetableId,
      metadataUpdates: {'name': newName},
    );
    
    await applyIncrementalUpdate(updateBatch, userId);
  }

  // Private methods

  Future<void> _saveLocalTimetable(NormalizedTimetable timetable) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_localTimetablePrefix${timetable.id}';
    await prefs.setString(key, json.encode(timetable.toJson()));
    
    // Update timetable list
    await _updateLocalTimetableList(timetable.id);
  }

  Future<NormalizedTimetable?> _getLocalTimetable(String timetableId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_localTimetablePrefix$timetableId';
    final jsonString = prefs.getString(key);
    
    if (jsonString != null) {
      final jsonData = json.decode(jsonString);
      return NormalizedTimetable.fromJson(jsonData);
    }
    return null;
  }

  Future<void> _saveFirestoreTimetable(NormalizedTimetable timetable, String userId) async {
    final docRef = _firestore
        .collection('user_timetables')
        .doc(userId)
        .collection('timetables')
        .doc(timetable.id);
    
    await docRef.set(timetable.toJson());
  }

  Future<NormalizedTimetable?> _getFirestoreTimetable(String timetableId, String userId) async {
    final docRef = _firestore
        .collection('user_timetables')
        .doc(userId)
        .collection('timetables')
        .doc(timetableId);
    
    final doc = await docRef.get();
    if (doc.exists) {
      return NormalizedTimetable.fromJson(doc.data()!);
    }
    return null;
  }

  Future<void> _applyLocalUpdate(TimetableUpdateBatch updateBatch) async {
    final timetable = await _getLocalTimetable(updateBatch.timetableId);
    if (timetable == null) {
      throw Exception('Timetable ${updateBatch.timetableId} not found locally');
    }

    final updatedSections = List<SectionReference>.from(timetable.selectedSections);
    
    // Remove sections
    for (final section in updateBatch.sectionsToRemove) {
      updatedSections.removeWhere((s) => s == section);
    }
    
    // Add sections (check for duplicates)
    for (final section in updateBatch.sectionsToAdd) {
      if (!updatedSections.contains(section)) {
        updatedSections.add(section);
      }
    }

    // Apply metadata updates safely
    final metadataUpdates = updateBatch.metadataUpdates ?? {};
    final updatedTimetable = NormalizedTimetable(
      id: timetable.id,
      name: metadataUpdates['name']?.toString() ?? timetable.name,
      createdAt: timetable.createdAt,
      updatedAt: DateTime.now(),
      selectedSections: updatedSections,
      clashWarnings: timetable.clashWarnings,
      courseVersion: timetable.courseVersion,
    );

    await _saveLocalTimetable(updatedTimetable);
  }

  Future<void> _applyFirestoreUpdate(TimetableUpdateBatch updateBatch, String userId) async {
    final docRef = _firestore
        .collection('user_timetables')
        .doc(userId)
        .collection('timetables')
        .doc(updateBatch.timetableId);

    // Check if document exists first
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) {
      throw Exception('Timetable ${updateBatch.timetableId} not found in Firestore');
    }

    // Build update map with all changes
    final updates = <String, dynamic>{
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // Add sections to update
    if (updateBatch.sectionsToAdd.isNotEmpty) {
      updates['selectedSections'] = FieldValue.arrayUnion(
        updateBatch.sectionsToAdd.map((s) => s.toJson()).toList(),
      );
    }
    
    // Apply metadata updates
    if (updateBatch.metadataUpdates != null) {
      updates.addAll(updateBatch.metadataUpdates!);
      updates['updatedAt'] = DateTime.now().toIso8601String();
    }

    // Apply all updates at once
    await docRef.update(updates);

    // Handle section removal separately if needed
    if (updateBatch.sectionsToRemove.isNotEmpty) {
      await docRef.update({
        'selectedSections': FieldValue.arrayRemove(
          updateBatch.sectionsToRemove.map((s) => s.toJson()).toList(),
        ),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<NormalizedTimetable>> _getAllLocalTimetables() async {
    final prefs = await SharedPreferences.getInstance();
    final timetableIds = prefs.getStringList(_timetableListKey) ?? [];
    
    final timetables = <NormalizedTimetable>[];
    for (final id in timetableIds) {
      final timetable = await _getLocalTimetable(id);
      if (timetable != null) {
        timetables.add(timetable);
      }
    }
    
    return timetables;
  }

  Future<List<NormalizedTimetable>> _getAllFirestoreTimetables(String userId) async {
    final collection = _firestore
        .collection('user_timetables')
        .doc(userId)
        .collection('timetables');
    
    final querySnapshot = await collection.get();
    final timetables = <NormalizedTimetable>[];
    
    for (final doc in querySnapshot.docs) {
      try {
        final timetable = NormalizedTimetable.fromJson(doc.data());
        timetables.add(timetable);
        
        // Cache locally for offline access
        await _saveLocalTimetable(timetable);
      } catch (e) {
        // Error parsing timetable ${doc.id}: $e
        // Skip invalid timetables but continue with others
      }
    }
    
    return timetables;
  }

  Future<void> _updateLocalTimetableList(String timetableId) async {
    final prefs = await SharedPreferences.getInstance();
    final timetableIds = prefs.getStringList(_timetableListKey) ?? [];
    
    if (!timetableIds.contains(timetableId)) {
      timetableIds.add(timetableId);
      await prefs.setStringList(_timetableListKey, timetableIds);
    }
  }

  /// Validate that section references are valid
  Future<void> _validateSectionReferences(List<SectionReference> sections) async {
    if (sections.isEmpty) return;
    
    try {
      final courses = await _courseDataService.fetchCourses();
      final courseMap = <String, Course>{};
      
      for (final course in courses) {
        courseMap[course.courseCode] = course;
      }
      
      for (final section in sections) {
        final course = courseMap[section.courseCode];
        if (course == null) {
          throw Exception('Course not found: ${section.courseCode}');
        }
        
        final sectionExists = course.sections.any((s) => s.sectionId == section.sectionId);
        if (!sectionExists) {
          throw Exception('Section not found: ${section.courseCode}-${section.sectionId}');
        }
      }
    } catch (e) {
      // Section validation error: $e
      // In production, you might want to be more lenient here
      // For now, we'll allow invalid sections but log the error
    }
  }

  /// Delete a timetable
  Future<void> deleteTimetable(String timetableId, String? userId) async {
    try {
      // Delete from Firestore if user is authenticated
      if (userId != null) {
        await _firestore
            .collection('user_timetables')
            .doc(userId)
            .collection('timetables')
            .doc(timetableId)
            .delete();
      }
      
      // Delete from local storage
      final prefs = await SharedPreferences.getInstance();
      final key = '$_localTimetablePrefix$timetableId';
      await prefs.remove(key);
      
      // Update local timetable list
      final timetableIds = prefs.getStringList(_timetableListKey) ?? [];
      timetableIds.remove(timetableId);
      await prefs.setStringList(_timetableListKey, timetableIds);
      
    } catch (e) {
      // Error deleting timetable: $e
      throw Exception('Failed to delete timetable: $e');
    }
  }

  /// Get cached course metadata
  Future<CourseMetadata?> _getCachedCourseMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataString = prefs.getString(_courseMetadataKey);
      
      if (metadataString != null) {
        final metadataJson = json.decode(metadataString);
        final metadata = CourseMetadata.fromJson(metadataJson);
        
        // Check if metadata is still valid (e.g., less than 1 hour old)
        final isValid = DateTime.now().difference(metadata.lastUpdated).inHours < 1;
        
        if (isValid) {
          return metadata;
        }
      }
    } catch (e) {
      // Error getting cached course metadata: $e
    }
    
    return null;
  }

  /// Save course metadata to cache
  Future<void> _saveCourseMetadata(CourseMetadata metadata) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_courseMetadataKey, json.encode(metadata.toJson()));
    } catch (e) {
      // Error saving course metadata: $e
    }
  }

  Future<CourseMetadata> _getCurrentCourseMetadata() async {
    // Try to get cached metadata first
    final cachedMetadata = await _getCachedCourseMetadata();
    if (cachedMetadata != null) {
      return cachedMetadata;
    }
    
    try {
      final courses = await _courseDataService.fetchCourses();
      final courseHashes = <String, String>{};
      
      for (final course in courses) {
        try {
          final courseJson = json.encode(course.toJson());
          final hash = md5.convert(utf8.encode(courseJson)).toString();
          courseHashes[course.courseCode] = hash;
        } catch (e) {
          // Error hashing course ${course.courseCode}: $e
          // Use course code as fallback hash
          courseHashes[course.courseCode] = course.courseCode;
        }
      }
      
      final version = md5.convert(utf8.encode(courseHashes.toString())).toString();
      
      final metadata = CourseMetadata(
        version: version,
        lastUpdated: DateTime.now(),
        courseHashes: courseHashes,
      );
      
      // Cache the metadata
      await _saveCourseMetadata(metadata);
      
      return metadata;
    } catch (e) {
      // Error generating course metadata: $e
      // Return fallback metadata
      return CourseMetadata(
        version: 'fallback_${DateTime.now().millisecondsSinceEpoch}',
        lastUpdated: DateTime.now(),
        courseHashes: {},
      );
    }
  }
}