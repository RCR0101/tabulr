import '../../models/course.dart';
import '../ui/secure_logger.dart';
import 'branch_structure_service.dart';

/// Derives the Open Elective (OPEL) pool.
///
/// An OPEL is any offered course that is neither a Discipline Elective (DEL)
/// nor a Humanities Elective (HUEL): OPEL = offered − (DEL ∪ HUEL). DEL and HUEL
/// codes are pooled across every branch, since a course that is a DEL for one
/// branch is still a DEL and so cannot double as an OPEL here.
class OpenElectivesService {
  final BranchStructureService _branchService = BranchStructureService();

  Future<List<Course>> getOpenElectives(List<Course> availableCourses) async {
    try {
      final branches = await _branchService.getAvailableBranches();

      final electiveCodes = <String>{};
      for (final branch in branches) {
        electiveCodes.addAll(await _branchService.getDELs(branch));
        electiveCodes.addAll(await _branchService.getHUELs(branch));
      }

      final result = availableCourses
          .where((c) => !electiveCodes.contains(c.courseCode))
          .toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));

      SecureLogger.debug(
          'OPEL', 'Found ${result.length} open electives of '
          '${availableCourses.length} offered');
      return result;
    } catch (e) {
      SecureLogger.error('OPEL', 'Error in getOpenElectives', e);
      rethrow;
    }
  }
}
