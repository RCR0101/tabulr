import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/branch_constants.dart' as constants;
import '../../constants/app_constants.dart';
import 'local_cache_service.dart';

class BranchStructure {
  final String branchCode;
  final Map<String, List<String>> cdcs;
  final List<String> dels;
  final List<String> huels;

  BranchStructure({
    required this.branchCode,
    required this.cdcs,
    required this.dels,
    required this.huels,
  });

  factory BranchStructure.fromMap(Map<String, dynamic> data) {
    final rawCdcs = data['cdcs'] as Map<String, dynamic>? ?? {};
    final cdcs = <String, List<String>>{};
    for (final entry in rawCdcs.entries) {
      cdcs[entry.key] = List<String>.from(entry.value as List? ?? []);
    }

    return BranchStructure(
      branchCode: data['branch_code'] as String? ?? '',
      cdcs: cdcs,
      dels: List<String>.from(data['dels'] as List? ?? []),
      huels: List<String>.from(data['huels'] as List? ?? []),
    );
  }

  List<String> cdcsForSemester(String semester) => cdcs[semester] ?? [];
}

class BranchStructureService {
  static final BranchStructureService _instance = BranchStructureService._();
  factory BranchStructureService() => _instance;
  BranchStructureService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalCacheService _localCache = LocalCacheService();
  final Map<String, BranchStructure> _cache = {};
  List<String>? _availableBranches;
  bool _loaded = false;

  static const _cacheKey = 'branch_structures';

  CollectionReference<Map<String, dynamic>> get _branchesRef =>
      _firestore.collection(FirestoreCollections.reference).doc(FirestoreCollections.branches).collection(FirestoreCollections.data);

  DocumentReference<Map<String, dynamic>> get _metadataRef =>
      _branchesRef.doc('_metadata');

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final cached = await _localCache.readIfFresh(
      _cacheKey,
      metadataRef: _metadataRef,
    );
    if (cached != null) {
      _populateFromRawDocs(cached);
      return;
    }

    final snapshot = await _branchesRef.get();
    final rawDocs = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['_docId'] = doc.id;
      rawDocs.add(data);
    }
    await _localCache.write(_cacheKey, rawDocs);
    _populateFromRawDocs(rawDocs);
  }

  void _populateFromRawDocs(List<Map<String, dynamic>> rawDocs) {
    _cache.clear();
    final branches = <String>[];
    for (final raw in rawDocs) {
      final docId = raw['_docId'] as String? ?? '';
      if (docId == '_metadata') {
        _availableBranches = List<String>.from(raw['branches'] as List? ?? []);
        continue;
      }
      final structure = BranchStructure.fromMap(raw);
      _cache[docId] = structure;
      if (docId.isNotEmpty) branches.add(docId);
    }
    _availableBranches ??= branches..sort();
    _loaded = true;
  }

  Future<List<String>> getAvailableBranches() async {
    await _ensureLoaded();
    if (_availableBranches != null) return _availableBranches!;
    _availableBranches = constants.branchCodeToName.keys.toList()..sort();
    return _availableBranches!;
  }

  Future<BranchStructure> getBranchData(String branchCode) async {
    await _ensureLoaded();
    return _cache[branchCode] ?? BranchStructure(
      branchCode: branchCode,
      cdcs: {},
      dels: [],
      huels: [],
    );
  }

  Future<List<String>> getCDCs(String branchCode, String? semester) async {
    final data = await getBranchData(branchCode);
    if (semester != null) return data.cdcsForSemester(semester);
    return data.cdcs.values.expand((v) => v).toList();
  }

  Future<List<String>> getDELs(String branchCode) async {
    final data = await getBranchData(branchCode);
    return data.dels;
  }

  Future<List<String>> getHUELs(String branchCode) async {
    final data = await getBranchData(branchCode);
    return data.huels;
  }

  Future<Map<String, List<String>>> getMergedCDCs(
    String mscBranch,
    String beBranch,
  ) async {
    final overrideKey = '${mscBranch}_$beBranch';
    final overrideData = await getBranchData(overrideKey);
    if (overrideData.cdcs.isNotEmpty) return overrideData.cdcs;

    final mscData = await getBranchData(mscBranch);
    final beData = await getBranchData(beBranch);

    final merged = <String, List<String>>{};

    for (final entry in mscData.cdcs.entries) {
      merged[entry.key] = List<String>.from(entry.value);
    }

    const semesterShift = {
      '2-1': '3-1',
      '2-2': '3-2',
      '3-1': '4-1',
      '3-2': '4-2',
    };

    for (final entry in beData.cdcs.entries) {
      final targetSem = semesterShift[entry.key];
      if (targetSem == null) continue;

      final existing = merged[targetSem] ?? [];
      final combined = <String>{...existing, ...entry.value};
      merged[targetSem] = combined.toList();
    }

    return merged;
  }

  Future<Set<String>> getCoreCourseCodes(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
  ) async {
    if (secondaryBranch != null &&
        constants.isMscBranch(primaryBranch) &&
        constants.isBeBranch(secondaryBranch)) {
      final merged = await getMergedCDCs(primaryBranch, secondaryBranch);
      final codes = <String>{};
      codes.addAll(merged[primarySemester] ?? []);
      if (secondarySemester != null) {
        codes.addAll(merged[secondarySemester] ?? []);
      }
      return codes;
    }

    final codes = <String>{};
    final primaryData = await getBranchData(primaryBranch);
    codes.addAll(primaryData.cdcsForSemester(primarySemester));

    if (secondaryBranch != null && secondarySemester != null) {
      final secondaryData = await getBranchData(secondaryBranch);
      codes.addAll(secondaryData.cdcsForSemester(secondarySemester));
    }

    return codes;
  }

  void clearCache() {
    _cache.clear();
    _availableBranches = null;
    _loaded = false;
    _localCache.invalidate(_cacheKey);
  }
}
