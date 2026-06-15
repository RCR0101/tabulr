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

  String _fileName(String key) => key.replaceAll('/', '_');

  static dynamic _sanitize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): _sanitize(e.value)};
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }

  Future<DateTime?> readCachedAt(String cacheKey) async {
    if (kIsWeb) return null;
    try {
      final file = File('${await _dir}/${_fileName(cacheKey)}.json');
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      final envelope = jsonDecode(content) as Map<String, dynamic>;
      return DateTime.parse(envelope['cachedAt'] as String);
    } catch (_) {
      return null;
    }
  }

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

  Future<void> write(String cacheKey, List<Map<String, dynamic>> data) async {
    if (kIsWeb) return;
    try {
      final file = File('${await _dir}/${_fileName(cacheKey)}.json');
      final envelope = {
        'cachedAt': DateTime.now().toIso8601String(),
        'data': _sanitize(data),
      };
      await file.writeAsString(jsonEncode(envelope));
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
