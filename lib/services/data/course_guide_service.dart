import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../ui/secure_logger.dart';
import 'branch_structure_service.dart';
import 'courses_master_service.dart';
import '../../utils/branch_constants.dart' as constants;

class CourseGuideService {
  static final CourseGuideService _instance = CourseGuideService._internal();
  factory CourseGuideService() => _instance;
  CourseGuideService._internal();

  final BranchStructureService _branchService = BranchStructureService();
  final CoursesMasterService _masterService = CoursesMasterService();

  Map<String, List<String>>? _duplicateMap;

  Future<Map<String, List<String>>> _getDuplicateMap() async {
    if (_duplicateMap != null) return _duplicateMap!;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reference')
          .doc('duplicate_courses')
          .get();
      final raw = doc.data()?['codeMap'] as Map<String, dynamic>? ?? {};
      _duplicateMap = raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (e) {
      SecureLogger.warning('CourseGuide', 'Failed to load duplicate courses: $e');
      _duplicateMap = {};
    }
    return _duplicateMap!;
  }

  bool _isDuplicate(String code, Set<String> seen, Map<String, List<String>> dupeMap) {
    if (seen.contains(code)) return true;
    final equivalents = dupeMap[code];
    if (equivalents != null) {
      for (final eq in equivalents) {
        if (seen.contains(eq)) return true;
      }
    }
    return false;
  }

  void _markSeen(String code, Set<String> seen) {
    seen.add(code);
  }

  Map<String, List<CourseGuideEntry>> _buildEntries(
    Map<String, List<String>> semesters,
    Map<String, List<String>> dupeMap,
  ) {
    final result = <String, List<CourseGuideEntry>>{};
    final seen = <String>{};

    final sortedKeys = semesters.keys.toList()..sort();
    for (final sem in sortedKeys) {
      final codes = semesters[sem]!;
      final entries = <CourseGuideEntry>[];
      for (final code in codes) {
        if (_isDuplicate(code, seen, dupeMap)) continue;
        _markSeen(code, seen);
        final master = _masterService.get(code);
        entries.add(CourseGuideEntry(
          code: code,
          name: master?.title ?? '',
          credits: master?.credits ?? 0,
          type: master?.type ?? 'Normal',
        ));
      }
      result[sem] = entries;
    }
    return result;
  }

  Future<List<String>> getAvailableBranches() async {
    return _branchService.getAvailableBranches();
  }

  /// Get CDCs for a single branch, optionally filtered by semester.
  Future<Map<String, List<CourseGuideEntry>>> getCDCsForBranch(
    String branchCode, {
    String? semester,
  }) async {
    final data = await _branchService.getBranchData(branchCode);
    final dupeMap = await _getDuplicateMap();

    final semesters = semester != null
        ? {semester: data.cdcsForSemester(semester)}
        : data.cdcs;

    return _buildEntries(semesters, dupeMap);
  }

  /// Get merged CDCs for MSc primary + BE secondary.
  /// BE semesters shift forward: 2-1→3-1, 2-2→3-2, etc.
  Future<Map<String, List<CourseGuideEntry>>> getMergedCDCs(
    String mscBranch,
    String beBranch, {
    String? semester,
  }) async {
    final merged = await _branchService.getMergedCDCs(mscBranch, beBranch);
    final dupeMap = await _getDuplicateMap();

    final semesters = semester != null
        ? {semester: merged[semester] ?? <String>[]}
        : merged;

    return _buildEntries(semesters, dupeMap);
  }
}

class CourseGuideEntry {
  final String code;
  final String name;
  final double credits;
  final String type;

  CourseGuideEntry({
    required this.code,
    required this.name,
    required this.credits,
    required this.type,
  });
}
