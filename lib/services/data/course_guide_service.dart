import 'branch_structure_service.dart';
import 'courses_master_service.dart';

class CourseGuideService {
  static final CourseGuideService _instance = CourseGuideService._internal();
  factory CourseGuideService() => _instance;
  CourseGuideService._internal();

  final BranchStructureService _branchService = BranchStructureService();
  final CoursesMasterService _masterService = CoursesMasterService();

  Map<String, List<CourseGuideEntry>> _buildEntries(
    Map<String, List<String>> semesters,
  ) {
    final result = <String, List<CourseGuideEntry>>{};

    final sortedKeys = semesters.keys.toList()..sort();
    for (final sem in sortedKeys) {
      final codes = semesters[sem]!;
      final entries = <CourseGuideEntry>[];
      for (final code in codes) {
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

  Future<Map<String, List<CourseGuideEntry>>> getCDCsForBranch(
    String branchCode, {
    String? semester,
  }) async {
    final data = await _branchService.getBranchData(branchCode);

    final semesters = semester != null
        ? {semester: data.cdcsForSemester(semester)}
        : data.cdcs;

    return _buildEntries(semesters);
  }

  Future<Map<String, List<CourseGuideEntry>>> getMergedCDCs(
    String mscBranch,
    String beBranch, {
    String? semester,
  }) async {
    final merged = await _branchService.getMergedCDCs(mscBranch, beBranch);

    final semesters = semester != null
        ? {semester: merged[semester] ?? <String>[]}
        : merged;

    return _buildEntries(semesters);
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
