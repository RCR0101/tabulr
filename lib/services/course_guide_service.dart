import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'secure_logger.dart';
import 'branch_structure_service.dart';
import 'courses_master_service.dart';
import '../utils/branch_constants.dart' as constants;

class CourseGuideService {
  static final CourseGuideService _instance = CourseGuideService._internal();
  factory CourseGuideService() => _instance;
  CourseGuideService._internal();

  final BranchStructureService _branchService = BranchStructureService();
  final CoursesMasterService _masterService = CoursesMasterService();

  Future<List<String>> getAvailableBranches() async {
    return _branchService.getAvailableBranches();
  }

  /// Get CDCs for a single branch, optionally filtered by semester.
  Future<Map<String, List<CourseGuideEntry>>> getCDCsForBranch(
    String branchCode, {
    String? semester,
  }) async {
    final data = await _branchService.getBranchData(branchCode);
    final result = <String, List<CourseGuideEntry>>{};

    final semesters = semester != null
        ? {semester: data.cdcsForSemester(semester)}
        : data.cdcs;

    for (final entry in semesters.entries) {
      result[entry.key] = entry.value.map((code) {
        final master = _masterService.get(code);
        return CourseGuideEntry(
          code: code,
          name: master?.title ?? '',
          credits: master?.credits ?? 0,
          type: master?.type ?? 'Normal',
        );
      }).toList();
    }

    return result;
  }

  /// Get merged CDCs for MSc primary + BE secondary.
  /// BE semesters shift forward: 2-1→3-1, 2-2→3-2, etc.
  Future<Map<String, List<CourseGuideEntry>>> getMergedCDCs(
    String mscBranch,
    String beBranch, {
    String? semester,
  }) async {
    final merged = await _branchService.getMergedCDCs(mscBranch, beBranch);
    final result = <String, List<CourseGuideEntry>>{};

    final semesters = semester != null
        ? {semester: merged[semester] ?? <String>[]}
        : merged;

    for (final entry in semesters.entries) {
      result[entry.key] = entry.value.map((code) {
        final master = _masterService.get(code);
        return CourseGuideEntry(
          code: code,
          name: master?.title ?? '',
          credits: master?.credits ?? 0,
          type: master?.type ?? 'Normal',
        );
      }).toList();
    }

    return result;
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
