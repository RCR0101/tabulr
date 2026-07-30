import '../../models/cdc_slot.dart';
import '../../utils/branch_constants.dart' as constants;
import 'branch_structure_service.dart';
import 'courses_master_service.dart';

class CourseGuideService {
  static final CourseGuideService _instance = CourseGuideService._internal();
  factory CourseGuideService() => _instance;
  CourseGuideService._internal();

  final BranchStructureService _branchService = BranchStructureService();
  final CoursesMasterService _masterService = CoursesMasterService();

  Map<String, List<CourseGuideSlot>> _buildSlots(
    Map<String, List<String>> semesters,
  ) {
    final result = <String, List<CourseGuideSlot>>{};

    final sortedKeys = semesters.keys.toList()..sort();
    for (final sem in sortedKeys) {
      result[sem] = [
        for (final slot in CdcSlot.parseAll(semesters[sem]!))
          CourseGuideSlot([for (final code in slot.options) _entry(code)]),
      ];
    }
    return result;
  }

  CourseGuideEntry _entry(String code) {
    final master = _masterService.get(code);
    return CourseGuideEntry(
      code: code,
      name: master?.title ?? '',
      // Contact hours where no unit count is published — otherwise every
      // U-series course in a guide renders as "0U".
      credits: master?.effectiveCredits ?? 0,
      isInCreditHours: master?.isInCreditHours ?? false,
      type: master?.type ?? 'Normal',
    );
  }

  Future<List<String>> getAvailableBranches() async {
    return _branchService.getAvailableBranches();
  }

  Future<Map<String, List<CourseGuideSlot>>> getCDCsForBranch(
    String branchCode, {
    String? semester,
  }) async {
    final data = await _branchService.getBranchData(branchCode);

    // The raw entries, not `cdcsForSemester` — that flattens choices, and a
    // guide that lists both halves of a choice as required is the bug this
    // whole thing exists to avoid.
    final semesters = semester != null
        ? {semester: data.cdcs[semester] ?? const <String>[]}
        : data.cdcs;

    return _buildSlots(semesters);
  }

  /// CDCs for a student's degree, dual or single.
  ///
  /// A dual degree is not the union of its two branches — the combination has
  /// its own CDC list (an override doc keyed `{msc}_{be}`), falling back to a
  /// year-shifted merge. Routing both cases through here keeps that rule in one
  /// place. Anything that is not an MSc + BE pair is treated as a single degree.
  Future<Map<String, List<CourseGuideSlot>>> getCDCsForDegree(
    String primaryBranch,
    String? secondaryBranch, {
    String? semester,
  }) async {
    final pair = constants.dualDegreePair(primaryBranch, secondaryBranch);
    if (pair != null) {
      return getMergedCDCs(pair.msc, pair.be, semester: semester);
    }
    return getCDCsForBranch(primaryBranch, semester: semester);
  }

  Future<Map<String, List<CourseGuideSlot>>> getMergedCDCs(
    String mscBranch,
    String beBranch, {
    String? semester,
  }) async {
    final merged = await _branchService.getMergedCDCs(mscBranch, beBranch);

    final semesters = semester != null
        ? {semester: merged[semester] ?? <String>[]}
        : merged;

    return _buildSlots(semesters);
  }
}

/// One row of the guide: a course the student must take, or a set of
/// alternatives they pick exactly one of. See [CdcSlot] for how a choice is
/// stored.
class CourseGuideSlot {
  const CourseGuideSlot(this.options);

  /// Never empty; more than one entry means the student chooses.
  final List<CourseGuideEntry> options;

  bool get isChoice => options.length > 1;

  /// The entry to show when there is only room for one — also the whole slot
  /// when it isn't a choice.
  CourseGuideEntry get first => options.first;
}

class CourseGuideEntry {
  final String code;
  final String name;
  final double credits;

  /// Whether [credits] is contact hours, so the guide can suffix it correctly
  /// rather than printing every U-series course as "9U".
  final bool isInCreditHours;
  final String type;

  CourseGuideEntry({
    required this.code,
    required this.name,
    required this.credits,
    this.isInCreditHours = false,
    required this.type,
  });
}
