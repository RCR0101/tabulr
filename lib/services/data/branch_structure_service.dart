import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/cdc_slot.dart';
import '../../utils/branch_constants.dart' as constants;
import '../../constants/app_constants.dart';
import 'local_cache_service.dart';

class BranchStructure {
  final String branchCode;

  /// Raw per-semester entries. An entry may be a single course code or an
  /// encoded [CdcSlot] choice, so read it through [slotsForSemester] or
  /// [cdcsForSemester] rather than treating elements as course codes.
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

  /// Every course code required at [semester], with any choice flattened to all
  /// of its alternatives — the right answer for "is this a core course?", which
  /// is what every caller of this asks.
  List<String> cdcsForSemester(String semester) =>
      CdcSlot.expandAll(cdcs[semester] ?? const []);

  /// The requirements at [semester], choices intact. For anything that has to
  /// show or resolve a choice rather than just recognise its courses.
  List<CdcSlot> slotsForSemester(String semester) =>
      CdcSlot.parseAll(cdcs[semester] ?? const []);
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
    return CdcSlot.expandAll(data.cdcs.values.expand((v) => v));
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

  /// Every course that counts as core for this degree at these semesters.
  ///
  /// A choice contributes *all* of its alternatives: the callers are elective
  /// pools and clash filters, which must not offer — or ignore — a course just
  /// because the student might end up taking the other half of the choice. Use
  /// [getCoreCourseSlots] where the choice itself matters.
  Future<Set<String>> getCoreCourseCodes(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
  ) async {
    final slots = await getCoreCourseSlots(
      primarySemester,
      primaryBranch,
      secondarySemester,
      secondaryBranch,
    );
    return {for (final slot in slots) ...slot.options};
  }

  /// [getCoreCourseCodes] with choices intact, in listed order.
  Future<List<CdcSlot>> getCoreCourseSlots(
    String primarySemester,
    String primaryBranch,
    String? secondarySemester,
    String? secondaryBranch,
  ) async {
    final raw = <String>[];
    final pair = constants.dualDegreePair(primaryBranch, secondaryBranch);
    if (pair != null) {
      final merged = await getMergedCDCs(pair.msc, pair.be);
      raw.addAll(merged[primarySemester] ?? const []);
      if (secondarySemester != null && secondarySemester != primarySemester) {
        raw.addAll(merged[secondarySemester] ?? const []);
      }
    } else {
      final primaryData = await getBranchData(primaryBranch);
      raw.addAll(primaryData.cdcs[primarySemester] ?? const []);

      if (secondaryBranch != null && secondarySemester != null) {
        final secondaryData = await getBranchData(secondaryBranch);
        raw.addAll(secondaryData.cdcs[secondarySemester] ?? const []);
      }
    }

    // Two branches can require the same course, and the same choice can appear
    // in both halves of a dual degree; either way the student takes it once.
    final seen = <String>{};
    return [
      for (final slot in CdcSlot.parseAll(raw))
        if (seen.add(slot.encode())) slot,
    ];
  }

  void clearCache() {
    _cache.clear();
    _availableBranches = null;
    _loaded = false;
    _localCache.invalidate(_cacheKey);
  }
}
