import '../../models/course.dart';
import '../ui/secure_logger.dart';
import 'branch_structure_service.dart';

/// Derives the Open Elective (OPEL) pool.
///
/// An OPEL is any offered course that isn't part of *your* degree requirements:
/// OPEL = offered − (CDC ∪ DEL ∪ HUEL) for the selected branch(es). It is
/// branch-relative on purpose — another discipline's core or elective is a
/// legitimate open elective for you, so only the chosen branch(es)' codes are
/// subtracted. All CDC semesters are excluded, since none of your cores count.
class OpenElectivesService {
  final BranchStructureService _branchService = BranchStructureService();

  Future<List<Course>> getOpenElectives(
    List<Course> availableCourses,
    List<String> branchCodes,
  ) async {
    try {
      final excludedCodes = <String>{};
      for (final branch in branchCodes) {
        if (branch.isEmpty) continue;
        excludedCodes.addAll(await _branchService.getCDCs(branch, null));
        excludedCodes.addAll(await _branchService.getDELs(branch));
        excludedCodes.addAll(await _branchService.getHUELs(branch));
      }

      final result = availableCourses
          .where((c) => !excludedCodes.contains(c.courseCode))
          .toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));

      SecureLogger.debug(
          'OPEL', 'Found ${result.length} open electives of '
          '${availableCourses.length} offered for ${branchCodes.join(", ")}');
      return result;
    } catch (e) {
      SecureLogger.error('OPEL', 'Error in getOpenElectives', e);
      rethrow;
    }
  }
}
