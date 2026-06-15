import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._();
  factory LocalCacheService() => _instance;
  LocalCacheService._();

  static const _maxAgeHours = 72;
  String? _cacheDir;

  Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    if (kIsWeb) return '';
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = '${appDir.path}/firestore_cache';
    await Directory(_cacheDir!).create(recursive: true);
    return _cacheDir!;
  }

  String _fileName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static dynamic _sanitize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): _sanitize(e.value)};
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }

  /// Reads cached data using TTL only (no metadata check).
  /// Use for data without a Firestore metadata doc (e.g. R2-sourced data).
  Future<List<Map<String, dynamic>>?> read(String cacheKey) async {
    if (kIsWeb) return null;
    try {
      final file = File('${await _dir}/${_fileName(cacheKey)}.json');
      if (!file.existsSync()) return null;

      final content = await file.readAsString();
      final envelope = jsonDecode(content) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(envelope['cachedAt'] as String);

      if (DateTime.now().difference(cachedAt).inHours >= _maxAgeHours) {
        return null;
      }

      return (envelope['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
    if (kIsWeb) return null;
    try {
      final file = File('${await _dir}/${_fileName(cacheKey)}.json');
      if (!file.existsSync()) return null;

      final content = await file.readAsString();
      final envelope = jsonDecode(content) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(envelope['cachedAt'] as String);

      if (DateTime.now().difference(cachedAt).inHours >= _maxAgeHours) {
        return null;
      }

      final metaSnap = await metadataRef.get();
      if (metaSnap.exists) {
        final lastUpdated = metaSnap.data()?[metadataField];
        if (lastUpdated != null) {
          final remoteTime = lastUpdated is Timestamp
              ? lastUpdated.toDate()
              : DateTime.tryParse(lastUpdated.toString());
          if (remoteTime != null && remoteTime.isAfter(cachedAt)) {
            return null;
          }
        }
      }

      return (envelope['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      // Parse error, network error, corrupt file — treat as stale.
      return null;
    }
  }

  Future<void> write(String cacheKey, List<Map<String, dynamic>> data) async {
    if (kIsWeb) return;
    try {
      final dir = await _dir;
      final tmpFile = File('$dir/${_fileName(cacheKey)}.tmp');
      final finalFile = File('$dir/${_fileName(cacheKey)}.json');
      final envelope = {
        'cachedAt': DateTime.now().toIso8601String(),
        'data': _sanitize(data),
      };
      await tmpFile.writeAsString(jsonEncode(envelope));
      await tmpFile.rename(finalFile.path);
    } catch (_) {}
  }

  Future<void> invalidate(String cacheKey) async {
    if (kIsWeb) return;
    try {
      final file = File('${await _dir}/${_fileName(cacheKey)}.json');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  Future<void> invalidateAll() async {
    if (kIsWeb) return;
    try {
      final dir = Directory(await _dir);
      if (dir.existsSync()) {
        await for (final entity in dir.list()) {
          if (entity is File) await entity.delete();
        }
      }
    } catch (_) {}
  }
}
