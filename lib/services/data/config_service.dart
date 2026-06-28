import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../ui/secure_logger.dart';
import 'local_cache_service.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  final LocalCacheService _localCache = LocalCacheService();
  static const _cacheKey = 'app_config';

  String get googleWebClientId => '497813124701-d5v3q5knljt4svch4l0b5q0cgv71o22l.apps.googleusercontent.com';

  // App Configuration
  String get appName => 'Tabulr';
  // Keep in sync with pubspec.yaml `version:` field.
  String get appVersion => '2.5.0';

  // Debug Settings
  bool get debugMode => false;
  bool get enableAnalytics => true;

  // ── Semester dates ──────────────────────────────────────────────────────
  //
  // Defaults are the fallback used until the remote config loads (or if it is
  // unavailable). Admin overrides from Firestore replace them at runtime via
  // [loadSemesterDates]; the getters stay synchronous so existing callers
  // (calendar, export) are unchanged.

  static final Map<String, DateTime> _defaults = {
    'semesterStart': DateTime(2026, 1, 5),
    'semesterEnd': DateTime(2026, 5, 16),
    'midsemStart': DateTime(2026, 3, 9),
    'midsemEnd': DateTime(2026, 3, 14),
    'endsemStart': DateTime(2026, 5, 2),
    'endsemEnd': DateTime(2026, 5, 16),
  };

  /// Ordered keys, also the order shown in the admin editor.
  static const List<String> dateKeys = [
    'semesterStart',
    'semesterEnd',
    'midsemStart',
    'midsemEnd',
    'endsemStart',
    'endsemEnd',
  ];

  static const Map<String, String> dateLabels = {
    'semesterStart': 'Semester start',
    'semesterEnd': 'Semester end',
    'midsemStart': 'Mid-sem start',
    'midsemEnd': 'Mid-sem end',
    'endsemStart': 'End-sem start',
    'endsemEnd': 'End-sem end',
  };

  final Map<String, DateTime> _overrides = {};
  bool _loaded = false;

  DocumentReference<Map<String, dynamic>> get _configRef => FirebaseFirestore
      .instance
      .collection(FirestoreCollections.reference)
      .doc('app_config');

  DateTime _date(String key) => _overrides[key] ?? _defaults[key]!;

  DateTime get semesterStart => _date('semesterStart');
  DateTime get semesterEnd => _date('semesterEnd');
  DateTime get midsemStart => _date('midsemStart');
  DateTime get midsemEnd => _date('midsemEnd');
  DateTime get endsemStart => _date('endsemStart');
  DateTime get endsemEnd => _date('endsemEnd');

  /// Current effective dates (override or default) for all keys.
  Map<String, DateTime> get semesterDates =>
      {for (final k in dateKeys) k: _date(k)};

  List<Map<String, DateTime>> get breakPeriods => [
        {'start': midsemStart, 'end': midsemEnd},
        {'start': endsemStart, 'end': endsemEnd},
      ];

  bool get isValidConfiguration => googleWebClientId.isNotEmpty;

  /// Load admin-set semester dates from Firestore, falling back to the local
  /// cache when offline. Safe to call at startup; idempotent unless [force].
  Future<void> loadSemesterDates({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final snap = await _configRef.get();
      final data = snap.data()?['semester_dates'] as Map<String, dynamic>?;
      if (data != null) {
        _applyMap(data);
        await _localCache.write(_cacheKey, [_serialize()]);
        _loaded = true;
        return;
      }
    } catch (e) {
      SecureLogger.error('CONFIG', 'Failed to load semester dates', e);
    }
    final cached = await _localCache.read(_cacheKey);
    if (cached != null && cached.isNotEmpty) _applyMap(cached.first);
    _loaded = true;
  }

  /// Persist admin-set semester dates and apply them in-memory immediately.
  Future<void> saveSemesterDates(Map<String, DateTime> dates) async {
    await _configRef.set({
      'semester_dates': {
        for (final e in dates.entries) e.key: e.value.toIso8601String(),
      },
      'updated_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    _overrides.addAll(dates);
    await _localCache.write(_cacheKey, [_serialize()]);
  }

  void _applyMap(Map<String, dynamic> map) {
    for (final key in dateKeys) {
      final v = map[key];
      final dt = v is Timestamp
          ? v.toDate()
          : (v is String ? DateTime.tryParse(v) : null);
      if (dt != null) _overrides[key] = dt;
    }
  }

  Map<String, dynamic> _serialize() =>
      {for (final k in dateKeys) k: _date(k).toIso8601String()};

  void printConfiguration() {
    if (debugMode) {
      SecureLogger.debug('CONFIG', 'App: $appName v$appVersion, debug=$debugMode, analytics=$enableAnalytics');
    }
  }
}
