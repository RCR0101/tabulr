import 'dart:convert';
import '../ui/secure_logger.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache for Firestore collections that change rarely.
///
/// Storage is abstracted so this works on **web too** — web previously bailed
/// out of every method, which meant returning users re-read whole collections
/// from the server on every page load. Native uses files; web uses
/// SharedPreferences (localStorage), which comfortably holds the few hundred KB
/// these catalogues occupy.
class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._();
  factory LocalCacheService() => _instance;
  LocalCacheService._();

  static const _maxAgeHours = 72;
  static const _webKeyPrefix = 'fs_cache_';
  String? _cacheDir;

  Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = '${appDir.path}/firestore_cache';
    await Directory(_cacheDir!).create(recursive: true);
    return _cacheDir!;
  }

  String _fileName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // --- storage primitives (web: SharedPreferences, native: files) ---

  Future<String?> _readRaw(String cacheKey) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_webKeyPrefix${_fileName(cacheKey)}');
    }
    final file = File('${await _dir}/${_fileName(cacheKey)}.json');
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  Future<void> _writeRaw(String cacheKey, String content) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_webKeyPrefix${_fileName(cacheKey)}', content);
      return;
    }
    final dir = await _dir;
    // Write-then-rename so a crash mid-write can't leave a corrupt cache file.
    final tmpFile = File('$dir/${_fileName(cacheKey)}.tmp');
    final finalFile = File('$dir/${_fileName(cacheKey)}.json');
    await tmpFile.writeAsString(content);
    await tmpFile.rename(finalFile.path);
  }

  Future<void> _deleteRaw(String cacheKey) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_webKeyPrefix${_fileName(cacheKey)}');
      return;
    }
    final file = File('${await _dir}/${_fileName(cacheKey)}.json');
    if (file.existsSync()) await file.delete();
  }

  static dynamic _sanitize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): _sanitize(e.value)};
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }

  /// Decodes an envelope and returns its payload if within [maxAge] hours.
  /// Returns null (treat as miss) on any parse problem.
  ({List<Map<String, dynamic>> data, DateTime cachedAt})? _decode(
    String? content,
    int maxAge,
  ) {
    if (content == null) return null;
    final envelope = jsonDecode(content) as Map<String, dynamic>;
    final cachedAt = DateTime.parse(envelope['cachedAt'] as String);
    if (DateTime.now().difference(cachedAt).inHours >= maxAge) return null;
    final data = (envelope['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return (data: data, cachedAt: cachedAt);
  }

  /// Reads cached data using TTL only (no metadata check).
  /// Use for data without a Firestore metadata doc (e.g. R2-sourced data).
  ///
  /// [maxAgeHours] overrides the default 72h TTL for rarely-changing data
  /// (e.g. the credits screen), where a longer-lived cache is desirable.
  Future<List<Map<String, dynamic>>?> read(
    String cacheKey, {
    int? maxAgeHours,
  }) async {
    try {
      final decoded =
          _decode(await _readRaw(cacheKey), maxAgeHours ?? _maxAgeHours);
      return decoded?.data;
    } catch (_) {
      return null;
    }
  }

  /// Reads cached data if it exists, is within TTL, and is not stale
  /// relative to [metadataRef]. Returns null if cache should be bypassed.
  ///
  /// The staleness check costs 1 Firestore read. On any error (network
  /// failure, missing doc, bad field) the cache is treated as **stale** so
  /// the caller falls through to a full fetch — correctness over speed.
  Future<List<Map<String, dynamic>>?> readIfFresh(
    String cacheKey, {
    required DocumentReference<Map<String, dynamic>> metadataRef,
    String metadataField = 'lastUpdated',
  }) async {
    try {
      final decoded = _decode(await _readRaw(cacheKey), _maxAgeHours);
      if (decoded == null) return null;

      final metaSnap = await metadataRef.get();
      if (metaSnap.exists) {
        final lastUpdated = metaSnap.data()?[metadataField];
        if (lastUpdated != null) {
          final remoteTime = lastUpdated is Timestamp
              ? lastUpdated.toDate()
              : DateTime.tryParse(lastUpdated.toString());
          if (remoteTime != null && remoteTime.isAfter(decoded.cachedAt)) {
            return null;
          }
        }
      }

      return decoded.data;
    } catch (_) {
      // Parse error, network error, corrupt file — treat as stale.
      return null;
    }
  }

  Future<void> write(String cacheKey, List<Map<String, dynamic>> data) async {
    try {
      await _writeRaw(
        cacheKey,
        jsonEncode({
          'cachedAt': DateTime.now().toIso8601String(),
          'data': _sanitize(data),
        }),
      );
    } catch (e) {
      SecureLogger.warning('LOCAL_CACHE', 'Cache write failed', {'cacheKey': cacheKey, 'error': e.toString()});
    }
  }

  Future<void> invalidate(String cacheKey) async {
    try {
      await _deleteRaw(cacheKey);
    } catch (e) {
      SecureLogger.warning('LOCAL_CACHE', 'Cache invalidate failed', {'cacheKey': cacheKey, 'error': e.toString()});
    }
  }

  Future<void> invalidateAll() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys().toList()) {
          if (key.startsWith(_webKeyPrefix)) await prefs.remove(key);
        }
        return;
      }
      final dir = Directory(await _dir);
      if (dir.existsSync()) {
        await for (final entity in dir.list()) {
          if (entity is File) await entity.delete();
        }
      }
    } catch (e) {
      SecureLogger.warning('LOCAL_CACHE', 'Cache clear-all failed', {'error': e.toString()});
    }
  }
}
