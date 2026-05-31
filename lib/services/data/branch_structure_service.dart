import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/branch_constants.dart' as constants;

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

  factory BranchStructure.fromFirestore(Map<String, dynamic> data) {
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
  final Map<String, BranchStructure> _cache = {};
  List<String>? _availableBranches;

  CollectionReference<Map<String, dynamic>> get _branchesRef =>
      _firestore.collection('reference').doc('branches').collection('data');

  Future<List<String>> getAvailableBranches() async {
    if (_availableBranches != null) return _availableBranches!;

    try {
      final metaDoc = await _branchesRef.doc('_metadata').get();
      if (metaDoc.exists) {
        final data = metaDoc.data()!;
        _availableBranches = List<String>.from(data['branches'] as List? ?? []);
        return _availableBranches!;
      }
    } catch (_) {}

    _availableBranches = constants.branchCodeToName.keys.toList()..sort();
    return _availableBranches!;
  }

  Future<BranchStructure> getBranchData(String branchCode) async {
    if (_cache.containsKey(branchCode)) return _cache[branchCode]!;

    final doc = await _branchesRef.doc(branchCode).get();
    if (!doc.exists) {
      final empty = BranchStructure(
        branchCode: branchCode,
        cdcs: {},
        dels: [],
        huels: [],
      );
      _cache[branchCode] = empty;
      return empty;
    }

    final structure = BranchStructure.fromFirestore(doc.data()!);
    _cache[branchCode] = structure;
    return structure;
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

  /// Returns CDC map for an MSc+BE dual degree combination.
  /// First checks for an override doc ({msc}_{be}). If it exists, uses that
  /// directly. Otherwise falls back to merging with semester shifting:
  /// BE 2-1 → 3-1, BE 2-2 → 3-2, BE 3-1 → 4-1, BE 3-2 → 4-2
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

  /// Get core course codes for clash detection, supporting MSc+BE merge.
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
  }
}
